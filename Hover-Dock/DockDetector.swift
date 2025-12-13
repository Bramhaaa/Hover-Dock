//
//  DockDetector.swift
//  Hover-Dock
//
//  Created by Bramha Bajannavar on 13/12/25.
//

import Foundation
import AppKit
import Combine

/// Detects when the mouse enters or exits the macOS Dock area.
/// Supports bottom, left, and right Dock positions.
class DockDetector: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isHoveringDock: Bool = false
    @Published var dockPosition: DockPosition = .bottom
    
    // MARK: - Types
    
    enum DockPosition: String {
        case bottom
        case left
        case right
    }
    
    // MARK: - Private Properties
    
    private var mouseTimer: Timer?
    private let pollInterval: TimeInterval = 0.05 // 50ms = 20 checks per second
    private let dockThickness: CGFloat = 80 // Estimated Dock size in pixels when visible
    private let dockAutoHideEdgeThickness: CGFloat = 5 // Edge zone for auto-hide (extreme edge only)
    
    // Auto-hide support
    private var isDockAutoHideEnabled: Bool = false
    private var mouseEnteredDockAreaTime: Date?
    private let autoHideHoverDelay: TimeInterval = 0.4 // Wait 400ms before considering Dock visible
    
    // MARK: - Lifecycle
    
    init() {
        detectDockPosition()
        startMouseTracking()
        observeDockPreferenceChanges()
    }
    
    deinit {
        stopMouseTracking()
    }
    
    // MARK: - Public Methods
    
    func startMouseTracking() {
        // Stop any existing timer
        stopMouseTracking()
        
        // Start polling mouse position
        mouseTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.checkMousePosition()
        }
        
        print("DockDetector: Mouse tracking started")
    }
    
    func stopMouseTracking() {
        mouseTimer?.invalidate()
        mouseTimer = nil
        print("DockDetector: Mouse tracking stopped")
    }
    
    // MARK: - Private Methods
    
    /// Reads the Dock position from macOS preferences
    private func detectDockPosition() {
        guard let defaults = UserDefaults(suiteName: "com.apple.dock") else {
            print("DockDetector: Could not access Dock preferences, using heuristic detection")
            dockPosition = detectDockPositionHeuristically()
            isDockAutoHideEnabled = false
            print("DockDetector: Heuristically detected Dock at \(dockPosition.rawValue)")
            return
        }
        
        // Read orientation
        let orientationString = defaults.string(forKey: "orientation") ?? ""
        
        if orientationString.isEmpty {
            print("DockDetector: Could not read orientation from preferences, using heuristic detection")
            dockPosition = detectDockPositionHeuristically()
        } else {
            dockPosition = DockPosition(rawValue: orientationString) ?? .bottom
            print("DockDetector: Dock position detected as \(dockPosition.rawValue) from preferences")
        }
        
        // Read auto-hide setting
        isDockAutoHideEnabled = defaults.bool(forKey: "autohide")
        print("DockDetector: Dock auto-hide is \(isDockAutoHideEnabled ? "ENABLED" : "DISABLED")")
    }
    
    /// Fallback heuristic: detect Dock position by observing where the Dock UI is actually visible
    private func detectDockPositionHeuristically() -> DockPosition {
        // Use Accessibility API to find Dock windows
        // This is a simple heuristic that checks screen bounds and Dock process
        
        guard let screen = NSScreen.main else {
            return .bottom
        }
        
        // Get the visible frame (excludes Dock and menu bar)
        let visibleFrame = screen.visibleFrame
        let fullFrame = screen.frame
        
        print("DockDetector: Screen full frame: \(fullFrame)")
        print("DockDetector: Screen visible frame: \(visibleFrame)")
        
        // Compare visible vs full frame to infer Dock position
        let leftDiff = visibleFrame.minX - fullFrame.minX
        let rightDiff = fullFrame.maxX - visibleFrame.maxX
        let bottomDiff = visibleFrame.minY - fullFrame.minY
        
        print("DockDetector: Frame diffs - left: \(leftDiff), right: \(rightDiff), bottom: \(bottomDiff)")
        
        // Dock causes a difference of 60-90 pixels typically
        if leftDiff > 50 {
            return .left
        } else if rightDiff > 50 {
            return .right
        } else {
            return .bottom
        }
    }
    
    /// Observes changes to Dock preferences (when user moves the Dock)
    private func observeDockPreferenceChanges() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(dockPreferencesChanged),
            name: NSNotification.Name("com.apple.dock.prefchanged"),
            object: nil
        )
    }
    
    @objc private func dockPreferencesChanged() {
        let oldPosition = dockPosition
        let oldAutoHide = isDockAutoHideEnabled
        
        detectDockPosition()
        
        if oldPosition != dockPosition {
            print("DockDetector: Dock position changed from \(oldPosition.rawValue) to \(dockPosition.rawValue)")
        }
        
        if oldAutoHide != isDockAutoHideEnabled {
            print("DockDetector: Dock auto-hide changed to \(isDockAutoHideEnabled ? "ENABLED" : "DISABLED")")
            mouseEnteredDockAreaTime = nil // Reset timer
        }
    }
    
    /// Checks current mouse position and determines if it's in the Dock area
    private func checkMousePosition() {
        guard let screen = NSScreen.main else {
            print("DockDetector: No main screen found")
            return
        }
        
        // Get global mouse position (origin at bottom-left)
        let mouseLocation = NSEvent.mouseLocation
        let screenFrame = screen.frame
        
        // Calculate Dock bounds based on current position and auto-hide state
        let dockRect = calculateDockRect(for: screenFrame, useAutoHideEdge: isDockAutoHideEnabled)
        
        // Check if mouse is inside Dock area
        let isInDockArea = dockRect.contains(mouseLocation)
        
        // Handle auto-hide logic
        let shouldConsiderInDock: Bool
        
        if isDockAutoHideEnabled {
            // Auto-hide enabled: check if Dock is actually visible
            if isInDockArea {
                // Check if Dock window is actually visible
                let isDockVisible = isDockWindowVisible()
                
                if isDockVisible {
                    shouldConsiderInDock = true
                    mouseEnteredDockAreaTime = nil // Reset timer since Dock is visible
                } else {
                    // Dock not visible yet
                    if mouseEnteredDockAreaTime == nil {
                        mouseEnteredDockAreaTime = Date()
                    }
                    shouldConsiderInDock = false
                }
            } else {
                // Mouse left the Dock area - reset timer
                mouseEnteredDockAreaTime = nil
                shouldConsiderInDock = false
            }
        } else {
            // Auto-hide disabled: immediate detection
            shouldConsiderInDock = isInDockArea
            mouseEnteredDockAreaTime = nil // Reset any timer
        }
        
        // Detect state change
        if shouldConsiderInDock != isHoveringDock {
            isHoveringDock = shouldConsiderInDock
            
            if shouldConsiderInDock {
                print("DockDetector: ✅ Mouse ENTERED Dock (position: \(dockPosition.rawValue), auto-hide: \(isDockAutoHideEnabled))")
                print("   → Mouse: (\(String(format: "%.0f", mouseLocation.x)), \(String(format: "%.0f", mouseLocation.y)))")
                print("   → Dock Rect: \(dockRect)")
            } else {
                print("DockDetector: ❌ Mouse EXITED Dock")
            }
        }
    }
    
    /// Checks if the Dock window is actually visible (for auto-hide support)
    private func isDockWindowVisible() -> Bool {
        // Use CGWindowListCopyWindowInfo to find visible Dock windows
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        
        // Look for Dock windows
        for window in windowList {
            // Check if this is a Dock window
            if let ownerName = window[kCGWindowOwnerName as String] as? String,
               ownerName == "Dock" {
                
                // Check if it's actually on screen (not hidden)
                if let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                   let width = bounds["Width"],
                   let height = bounds["Height"],
                   width > 10 && height > 10 { // Dock has significant size when visible
                    return true
                }
            }
        }
        
        return false
    }
    
    /// Calculates the Dock rectangle based on screen bounds and Dock position
    private func calculateDockRect(for screenFrame: CGRect, useAutoHideEdge: Bool = false) -> CGRect {
        // Use thin edge detection for auto-hide mode
        let thickness = useAutoHideEdge ? dockAutoHideEdgeThickness : dockThickness
        
        switch dockPosition {
        case .bottom:
            // Bottom Dock: full width, bottom edge
            return CGRect(
                x: screenFrame.minX,
                y: screenFrame.minY,
                width: screenFrame.width,
                height: thickness
            )
            
        case .left:
            // Left Dock: full height, left edge
            return CGRect(
                x: screenFrame.minX,
                y: screenFrame.minY,
                width: thickness,
                height: screenFrame.height
            )
            
        case .right:
            // Right Dock: full height, right edge
            return CGRect(
                x: screenFrame.maxX - thickness,
                y: screenFrame.minY,
                width: thickness,
                height: screenFrame.height
            )
        }
    }
}
