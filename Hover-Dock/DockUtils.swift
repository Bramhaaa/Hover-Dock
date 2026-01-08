//
//  DockUtils.swift
//  Hover-Dock
//
//  Utilities for Dock position and state management
//

import Cocoa

enum DockPosition {
    case top
    case bottom
    case left
    case right
    case unknown
    
    var isHorizontal: Bool {
        switch self {
        case .top, .bottom:
            return true
        case .left, .right:
            return false
        case .unknown:
            return true
        }
    }
    
    var displayName: String {
        switch self {
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .left: return "Left"
        case .right: return "Right"
        case .unknown: return "Unknown"
        }
    }
}

class DockUtils {
    /// Get the current Dock position using private API
    static func getDockPosition() -> DockPosition {
        var orientation: Int32 = 0
        var pinning: Int32 = 0
        CoreDockGetOrientationAndPinning(&orientation, &pinning)
        
        switch orientation {
        case 1: return .top
        case 2: return .bottom
        case 3: return .left
        case 4: return .right
        default: return .unknown
        }
    }
    
    /// Returns the dock size in pixels based on the screen's visible frame
    static func getDockSize() -> CGFloat {
        guard let screen = NSScreen.main else { return 0 }
        let dockPosition = getDockPosition()
        
        switch dockPosition {
        case .right:
            return screen.frame.width - screen.visibleFrame.width
        case .left:
            return screen.visibleFrame.origin.x
        case .bottom:
            return screen.visibleFrame.origin.y
        case .top:
            return screen.frame.height - screen.visibleFrame.maxY
        case .unknown:
            return 0
        }
    }
    
    /// Check if Dock auto-hide is enabled
    static func isAutoHideEnabled() -> Bool {
        CoreDockGetAutoHideEnabled()
    }
}
