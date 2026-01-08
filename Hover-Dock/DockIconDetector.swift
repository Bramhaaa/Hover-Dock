//
//  DockIconDetector.swift
//  Hover-Dock
//
//  Created by Bramha Bajannavar on 30/12/25.
//

import Foundation
import AppKit
import ApplicationServices

/// Result of checking the Dock item under mouse
struct DockItemResult {
    enum Status {
        case success(NSRunningApplication)
        case notRunning(bundleIdentifier: String)
        case notFound
    }
    
    let status: Status
    let dockItemElement: AXUIElement?
}

// Callback function for AXObserver
func handleSelectedDockItemChanged(
    observer: AXObserver,
    element: AXUIElement,
    notificationName: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    // Use the singleton instance instead of refcon
    DockIconDetector.shared?.processSelectionChanged()
}

/// Detects which Dock icon the mouse is hovering over using AXObserver notifications
class DockIconDetector: ObservableObject {
    
    // MARK: - Singleton
    
    static weak var shared: DockIconDetector?
    
    // MARK: - Published Properties
    
    @Published var hoveredApp: NSRunningApplication?
    @Published var hoveredDockItem: AXUIElement?
    @Published var hoveredIconCenter: CGPoint?
    
    // MARK: - Private Properties
    
    private var axObserver: AXObserver?
    private var currentDockPID: pid_t?
    
    // MARK: - Initialization
    
    init() {
        Self.shared = self
        setupDockObserver()
    }
    
    deinit {
        Self.shared = nil
        teardownObserver()
    }
    
    // MARK: - Observer Setup
    
    private func setupDockObserver() {
        // Find the Dock process
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            print("DockIconDetector: Cannot find Dock process")
            return
        }
        
        let dockPID = dockApp.processIdentifier
        currentDockPID = dockPID
        
        // Check accessibility permissions
        guard AXIsProcessTrusted() else {
            print("DockIconDetector: ⚠️ No accessibility permissions")
            return
        }
        
        // Create AXUIElement for Dock
        let dockElement = AXUIElementCreateApplication(dockPID)
        
        // Get Dock's children to find the list
        guard let children = try? dockElement.children(),
              let dockList = children.first(where: { element in
                  (try? element.role()) == kAXListRole
              }) else {
            print("DockIconDetector: Cannot find Dock's AXList")
            return
        }
        
        // Create observer with callback (no context needed - using singleton pattern)
        let result = AXObserverCreate(dockPID, handleSelectedDockItemChanged, &axObserver)
        
        guard result == .success, let observer = axObserver else {
            print("DockIconDetector: Failed to create AXObserver: \(result.rawValue)")
            return
        }
        
        // Subscribe to selection changes - THIS IS THE KEY!
        do {
            try dockList.subscribeToNotification(observer, kAXSelectedChildrenChangedNotification) {
                // Add observer to run loop
                CFRunLoopAddSource(
                    CFRunLoopGetCurrent(),
                    AXObserverGetRunLoopSource(observer),
                    .commonModes
                )
                print("DockIconDetector: ✅ Successfully subscribed to Dock selection changes")
            }
        } catch {
            print("DockIconDetector: Failed to subscribe to notifications: \(error)")
        }
    }
    
    private func teardownObserver() {
        if let observer = axObserver {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        axObserver = nil
        currentDockPID = nil
    }
    
    // MARK: - Selection Changed Handler
    
    /// Called when the Dock's selected item changes (notification callback)
    func processSelectionChanged() {
        // Get the currently selected Dock item
        let result = getSelectedDockItem()
        
        guard case .success(let app) = result.status else {
            // No valid app selected, clear state
            DispatchQueue.main.async { [weak self] in
                self?.hoveredApp = nil
                self?.hoveredDockItem = nil
                self?.hoveredIconCenter = nil
            }
            return
        }
        
        // Update state on main thread
        DispatchQueue.main.async { [weak self] in
            self?.hoveredApp = app
            self?.hoveredDockItem = result.dockItemElement
            self?.hoveredIconCenter = self?.calculateIconCenter(result.dockItemElement)
            
            print("DockIconDetector: ✅ Hovered app: \(app.localizedName ?? "Unknown")")
        }
    }
    
    // MARK: - Getting Selected Dock Item
    
    /// Get the currently selected (hovered) Dock item using kAXSelectedChildrenAttribute
    private func getSelectedDockItem() -> DockItemResult {
        guard let dockPID = currentDockPID else {
            return DockItemResult(status: .notFound, dockItemElement: nil)
        }
        
        let dockElement = AXUIElementCreateApplication(dockPID)
        
        // Get Dock's children
        var dockItems: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockElement, kAXChildrenAttribute as CFString, &dockItems) == .success,
              let items = dockItems as? [AXUIElement],
              !items.isEmpty else {
            return DockItemResult(status: .notFound, dockItemElement: nil)
        }
        
        // Get selected children - THIS IS THE KEY ATTRIBUTE!
        var selectedChildren: CFTypeRef?
        guard AXUIElementCopyAttributeValue(items.first!, kAXSelectedChildrenAttribute as CFString, &selectedChildren) == .success,
              let selected = selectedChildren as? [AXUIElement],
              let hoveredItem = selected.first else {
            return DockItemResult(status: .notFound, dockItemElement: nil)
        }
        
        // Check if it's an application dock item
        guard (try? hoveredItem.subrole()) == "AXApplicationDockItem" else {
            return DockItemResult(status: .notFound, dockItemElement: nil)
        }
        
        // Get the app from the Dock item
        return getAppFromDockItem(hoveredItem)
    }
    
    /// Extract the NSRunningApplication from a Dock item element
    private func getAppFromDockItem(_ dockItem: AXUIElement) -> DockItemResult {
        do {
            // Get the URL attribute - this points to the .app bundle
            guard let appURL = try dockItem.attribute(kAXURLAttribute, NSURL.self),
                  let url = appURL.absoluteURL else {
                return DockItemResult(status: .notFound, dockItemElement: dockItem)
            }
            
            // Get bundle from URL
            let bundle = Bundle(url: url)
            guard let bundleIdentifier = bundle?.bundleIdentifier else {
                // Fallback: try to get title and match by name
                if let title = try dockItem.title(),
                   let app = findRunningAppByName(title) {
                    return DockItemResult(status: .success(app), dockItemElement: dockItem)
                }
                return DockItemResult(status: .notFound, dockItemElement: dockItem)
            }
            
            // Find running app by bundle identifier
            if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
                return DockItemResult(status: .success(runningApp), dockItemElement: dockItem)
            } else {
                return DockItemResult(status: .notRunning(bundleIdentifier: bundleIdentifier), dockItemElement: dockItem)
            }
        } catch {
            return DockItemResult(status: .notFound, dockItemElement: dockItem)
        }
    }
    
    /// Find running application by name (fallback method)
    private func findRunningAppByName(_ name: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { app in
            app.localizedName?.caseInsensitiveCompare(name) == .orderedSame
        }
    }
    
    // MARK: - Icon Position Calculation
    
    private func calculateIconCenter(_ dockItem: AXUIElement?) -> CGPoint? {
        guard let item = dockItem else { return nil }
        
        do {
            guard let position = try item.position(),
                  let size = try item.size() else {
                return nil
            }
            
            // Calculate center point
            return CGPoint(
                x: position.x + size.width / 2,
                y: position.y + size.height / 2
            )
        } catch {
            return nil
        }
    }
}
