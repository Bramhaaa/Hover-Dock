//
//  WindowDiscovery.swift
//  Hover-Dock
//
//  Created by Bramha Bajannavar on 30/12/25.
//

import Foundation
import AppKit
import ApplicationServices

/// Represents a window with metadata
struct WindowInfo: Identifiable, Equatable {
    let id: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let title: String
    let bounds: CGRect
    let layer: Int
    let isOnScreen: Bool
    let alpha: CGFloat
    var isMinimized: Bool = false
    var isHidden: Bool = false
    var isFullscreen: Bool = false
    var axElement: AXUIElement?
    
    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Discovers and manages windows for applications
class WindowDiscovery: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var discoveredWindows: [WindowInfo] = []
    
    // MARK: - Public Methods
    
    /// Discovers all windows for a specific application
    func discoverWindows(for app: NSRunningApplication) -> [WindowInfo] {
        // Use .optionAll to get ALL windows (including minimized and off-screen)
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            print("WindowDiscovery: Failed to get window list")
            return []
        }
        
        var windows: [WindowInfo] = []
        
        for window in windowList {
            // Filter by process ID
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == app.processIdentifier else {
                continue
            }
            
            // Get window ID
            guard let windowID = window[kCGWindowNumber as String] as? CGWindowID else {
                continue
            }
            
            // Get window bounds
            guard let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let width = boundsDict["Width"],
                  let height = boundsDict["Height"] else {
                continue
            }
            
            let bounds = CGRect(x: x, y: y, width: width, height: height)
            
            // Get window metadata
            let ownerName = window[kCGWindowOwnerName as String] as? String ?? app.localizedName ?? "Unknown"
            let title = window[kCGWindowName as String] as? String ?? ""
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            let alpha = window[kCGWindowAlpha as String] as? CGFloat ?? 1.0
            
            // Filter out invalid windows
            if !isValidWindow(bounds: bounds, layer: layer, alpha: alpha, title: title) {
                continue
            }
            
            // Get AX element for this window to check state
            let axApp = AXUIElementCreateApplication(ownerPID)
            var (isMinimized, isHidden, isFullscreen, axElement) = checkWindowState(axApp: axApp, windowTitle: title)
            
            // Skip fullscreen windows
            if isFullscreen {
                continue
            }
            
            let windowInfo = WindowInfo(
                id: windowID,
                ownerPID: ownerPID,
                ownerName: ownerName,
                title: title,
                bounds: bounds,
                layer: layer,
                isOnScreen: true,
                alpha: alpha,
                isMinimized: isMinimized,
                isHidden: isHidden,
                isFullscreen: isFullscreen,
                axElement: axElement
            )
            
            windows.append(windowInfo)
        }
        
        print("WindowDiscovery: Found \(windows.count) windows for \(app.localizedName ?? "app")")
        
        // Sort by window position (top to bottom, left to right)
        windows.sort { w1, w2 in
            if abs(w1.bounds.minY - w2.bounds.minY) < 50 {
                return w1.bounds.minX < w2.bounds.minX
            }
            return w1.bounds.minY > w2.bounds.minY // Higher windows first (inverted Y)
        }
        
        discoveredWindows = windows
        return windows
    }
    
    /// Discovers windows on the current Space only
    func discoverWindowsOnCurrentSpace(for app: NSRunningApplication) -> [WindowInfo] {
        // Get all windows for the app
        let allWindows = discoverWindows(for: app)
        
        // Filter to current Space using CGWindowListCopyWindowInfo with .optionOnScreenOnly
        // This already filters to current Space by default
        return allWindows
    }
    
    /// Gets a specific window's information
    func getWindowInfo(windowID: CGWindowID) -> WindowInfo? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let window = windowList.first else {
            return nil
        }
        
        guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
              let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
              let x = boundsDict["X"],
              let y = boundsDict["Y"],
              let width = boundsDict["Width"],
              let height = boundsDict["Height"] else {
            return nil
        }
        
        let bounds = CGRect(x: x, y: y, width: width, height: height)
        let ownerName = window[kCGWindowOwnerName as String] as? String ?? ""
        let title = window[kCGWindowName as String] as? String ?? ""
        let layer = window[kCGWindowLayer as String] as? Int ?? 0
        let alpha = window[kCGWindowAlpha as String] as? CGFloat ?? 1.0
        let isOnScreen = window[kCGWindowIsOnscreen as String] as? Bool ?? false
        
        return WindowInfo(
            id: windowID,
            ownerPID: ownerPID,
            ownerName: ownerName,
            title: title,
            bounds: bounds,
            layer: layer,
            isOnScreen: isOnScreen,
            alpha: alpha
        )
    }
    
    // MARK: - Private Methods
    
    /// Check window state (minimized, hidden, fullscreen)
    private func checkWindowState(axApp: AXUIElement, windowTitle: String) -> (isMinimized: Bool, isHidden: Bool, isFullscreen: Bool, axElement: AXUIElement?) {
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return (false, false, false, nil)
        }
        
        for axWindow in windows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
            
            if let title = titleRef as? String, title == windowTitle {
                // Check minimized state
                var minimizedRef: CFTypeRef?
                var isMinimized = false
                if AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
                   let minimized = minimizedRef as? Bool {
                    isMinimized = minimized
                }
                
                // Check hidden state (at app level)
                var hiddenRef: CFTypeRef?
                var isHidden = false
                if AXUIElementCopyAttributeValue(axApp, kAXHiddenAttribute as CFString, &hiddenRef) == .success,
                   let hidden = hiddenRef as? Bool {
                    isHidden = hidden
                }
                
                // Check fullscreen state
                var fullscreenRef: CFTypeRef?
                var isFullscreen = false
                if AXUIElementCopyAttributeValue(axWindow, kAXFullscreenAttribute as CFString, &fullscreenRef) == .success,
                   let fullscreen = fullscreenRef as? Bool {
                    isFullscreen = fullscreen
                }
                
                return (isMinimized, isHidden, isFullscreen, axWindow)
            }
        }
        
        return (false, false, false, nil)
    }
    
    /// Validates if a window should be shown
    private func isValidWindow(bounds: CGRect, layer: Int, alpha: CGFloat, title: String) -> Bool {
        // Filter out tiny windows (likely UI elements)
        if bounds.width < 50 || bounds.height < 50 {
            return false
        }
        
        // Filter out invisible windows
        if alpha < 0.1 {
            return false
        }
        
        // Only show normal layer windows (layer 0)
        // Higher layers are typically popups, overlays, etc.
        if layer != 0 {
            return false
        }
        
        // Filter out specific window titles that are not user windows
        let excludedTitles = [
            "Item-0", // Dock items
            "Window", // Generic system windows
            "Menubar",
            "StatusBar"
        ]
        
        if excludedTitles.contains(title) {
            return false
        }
        
        return true
    }
    
    /// Gets windows for all running applications (for debugging)
    func discoverAllWindows() -> [String: [WindowInfo]] {
        var appWindows: [String: [WindowInfo]] = [:]
        
        let runningApps = NSWorkspace.shared.runningApplications.filter { app in
            return app.activationPolicy == .regular && !app.isTerminated
        }
        
        for app in runningApps {
            let windows = discoverWindows(for: app)
            if !windows.isEmpty {
                appWindows[app.localizedName ?? "Unknown"] = windows
            }
        }
        
        return appWindows
    }
}

// MARK: - Window Actions

extension WindowDiscovery {
    
    /// Focus a specific window
    func focusWindow(_ windowInfo: WindowInfo) {
        guard let app = NSRunningApplication(processIdentifier: windowInfo.ownerPID) else {
            print("WindowDiscovery: Failed to get app for PID \(windowInfo.ownerPID)")
            return
        }
        
        // Activate the application
        app.activate(options: .activateIgnoringOtherApps)
        
        // Use Accessibility API to focus specific window
        let axApp = AXUIElementCreateApplication(windowInfo.ownerPID)
        
        // Get all windows
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard result == .success,
              let windows = windowsRef as? [AXUIElement] else {
            print("WindowDiscovery: Failed to get AX windows")
            return
        }
        
        // Find matching window by title
        for axWindow in windows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
            
            if let title = titleRef as? String, title == windowInfo.title {
                // Raise this window to front
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                
                // Set as focused window
                AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, axWindow)
                
                print("WindowDiscovery: Focused window '\(title)'")
                return
            }
        }
        
        print("WindowDiscovery: Could not find matching AX window")
    }
    
    /// Close a specific window
    func closeWindow(_ windowInfo: WindowInfo) {
        let axApp = AXUIElementCreateApplication(windowInfo.ownerPID)
        
        // Get all windows
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard result == .success,
              let windows = windowsRef as? [AXUIElement] else {
            print("WindowDiscovery: Failed to get AX windows for close")
            return
        }
        
        // Find matching window
        for axWindow in windows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
            
            if let title = titleRef as? String, title == windowInfo.title {
                // Get close button
                var closeButtonRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXCloseButtonAttribute as CFString, &closeButtonRef)
                
                if let closeButton = closeButtonRef {
                    // Press close button
                    AXUIElementPerformAction(closeButton as! AXUIElement, kAXPressAction as CFString)
                    print("WindowDiscovery: Closed window '\(title)'")
                    return
                }
            }
        }
        
        print("WindowDiscovery: Could not find window to close")
    }
    
    /// Minimize a specific window
    func minimizeWindow(_ windowInfo: WindowInfo) {
        guard let axElement = windowInfo.axElement else {
            print("WindowDiscovery: No AX element for window")
            return
        }
        
        // Toggle minimize state
        if windowInfo.isMinimized {
            // Un-minimize
            AXUIElementSetAttributeValue(axElement, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            // Bring to front
            AXUIElementPerformAction(axElement, kAXRaiseAction as CFString)
            print("WindowDiscovery: Un-minimized window '\(windowInfo.title)'")
        } else {
            // Minimize
            AXUIElementSetAttributeValue(axElement, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            print("WindowDiscovery: Minimized window '\(windowInfo.title)'")
        }
    }
}
