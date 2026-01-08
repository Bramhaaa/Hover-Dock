//
//  AXUIElementExtensions.swift
//  Hover-Dock
//
//  Extensions for AXUIElement to simplify accessibility API usage
//

import ApplicationServices
import Cocoa

extension AXUIElement {
    // MARK: - Error Handling
    
    func axCallWhichCanThrow<T>(_ result: AXError, _ successValue: inout T) throws -> T? {
        switch result {
        case .success: 
            return successValue
        case .cannotComplete: 
            throw AxError.runtimeError
        default: 
            return nil
        }
    }
    
    // MARK: - Window ID
    
    func cgWindowId() throws -> CGWindowID? {
        var id = CGWindowID(0)
        return try axCallWhichCanThrow(_AXUIElementGetWindow(self, &id), &id)
    }
    
    // MARK: - Process ID
    
    func pid() throws -> pid_t? {
        var pid = pid_t(0)
        return try axCallWhichCanThrow(AXUIElementGetPid(self, &pid), &pid)
    }
    
    // MARK: - Generic Attribute Access
    
    func attribute<T>(_ key: String, _ _: T.Type) throws -> T? {
        var value: AnyObject?
        return try axCallWhichCanThrow(AXUIElementCopyAttributeValue(self, key as CFString, &value), &value) as? T
    }
    
    private func value<T>(_ key: String, _ target: T, _ type: AXValueType) throws -> T? {
        if let a = try attribute(key, AXValue.self) {
            var value = target
            let success = withUnsafeMutablePointer(to: &value) { ptr in
                AXValueGetValue(a, type, ptr)
            }
            return success ? value : nil
        }
        return nil
    }
    
    // MARK: - Position & Size
    
    func position() throws -> CGPoint? {
        try value(kAXPositionAttribute, CGPoint.zero, .cgPoint)
    }
    
    func size() throws -> CGSize? {
        try value(kAXSizeAttribute, CGSize.zero, .cgSize)
    }
    
    // MARK: - Text Attributes
    
    func title() throws -> String? {
        try attribute(kAXTitleAttribute, String.self)
    }
    
    // MARK: - Hierarchy
    
    func parent() throws -> AXUIElement? {
        try attribute(kAXParentAttribute, AXUIElement.self)
    }
    
    func children() throws -> [AXUIElement]? {
        try attribute(kAXChildrenAttribute, [AXUIElement].self)
    }
    
    func windows() throws -> [AXUIElement]? {
        try attribute(kAXWindowsAttribute, [AXUIElement].self)
    }
    
    // MARK: - Window State
    
    func isMinimized() throws -> Bool {
        try attribute(kAXMinimizedAttribute, Bool.self) == true
    }
    
    func isFullscreen() throws -> Bool {
        try attribute(kAXFullscreenAttribute, Bool.self) == true
    }
    
    func focusedWindow() throws -> AXUIElement? {
        try attribute(kAXFocusedWindowAttribute, AXUIElement.self)
    }
    
    // MARK: - Role & Subrole
    
    func role() throws -> String? {
        try attribute(kAXRoleAttribute, String.self)
    }
    
    func subrole() throws -> String? {
        try attribute(kAXSubroleAttribute, String.self)
    }
    
    // MARK: - App State
    
    func appIsRunning() throws -> Bool? {
        try attribute(kAXIsApplicationRunningAttribute, Bool.self)
    }
    
    // MARK: - Window Buttons
    
    func closeButton() throws -> AXUIElement? {
        try attribute(kAXCloseButtonAttribute, AXUIElement.self)
    }
    
    func minimizeButton() throws -> AXUIElement? {
        try attribute(kAXMinimizeButtonAttribute, AXUIElement.self)
    }
    
    func zoomButton() throws -> AXUIElement? {
        try attribute(kAXZoomButtonAttribute, AXUIElement.self)
    }
    
    // MARK: - Notifications
    
    func subscribeToNotification(_ axObserver: AXObserver, _ notification: String, _ callback: (() -> Void)? = nil) throws {
        let result = AXObserverAddNotification(axObserver, self, notification as CFString, nil)
        if result == .success || result == .notificationAlreadyRegistered {
            callback?()
        } else if result != .notificationUnsupported, result != .notImplemented {
            throw AxError.runtimeError
        }
    }
    
    // MARK: - Attribute Setting
    
    func setAttribute(_ key: String, _ value: Any) throws {
        var unused: Void = ()
        try axCallWhichCanThrow(AXUIElementSetAttributeValue(self, key as CFString, value as CFTypeRef), &unused)
    }
    
    // MARK: - Actions
    
    func performAction(_ action: String) throws {
        var unused: Void = ()
        try axCallWhichCanThrow(AXUIElementPerformAction(self, action as CFString), &unused)
    }
}

enum AxError: Error {
    case runtimeError
}

extension AXValue {
    static func from(point: CGPoint) -> AXValue? {
        var point = point
        return AXValueCreate(.cgPoint, &point)
    }
    
    static func from(size: CGSize) -> AXValue? {
        var size = size
        return AXValueCreate(.cgSize, &size)
    }
    
    static func from(rect: CGRect) -> AXValue? {
        var rect = rect
        return AXValueCreate(.cgRect, &rect)
    }
}
