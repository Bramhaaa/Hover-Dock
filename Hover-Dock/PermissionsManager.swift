//
//  PermissionsManager.swift
//  Hover-Dock
//
//  Created by Bramha Bajannavar on 30/12/25.
//

import Foundation
import AppKit
import ApplicationServices

/// Manages permission checks and requests for Accessibility and Screen Recording
class PermissionsManager: ObservableObject {
    
    @Published var hasAccessibilityPermission: Bool = false
    @Published var hasScreenRecordingPermission: Bool = false
    
    // MARK: - Singleton
    
    static let shared = PermissionsManager()
    
    private init() {
        checkPermissions()
    }
    
    // MARK: - Permission Checks
    
    func checkPermissions() {
        hasAccessibilityPermission = checkAccessibilityPermission()
        hasScreenRecordingPermission = checkScreenRecordingPermission()
    }
    
    func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }
    
    func checkScreenRecordingPermission() -> Bool {
        // Check if we can capture screen content
        // This will trigger permission prompt on first call
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        
        // Try to capture a window to verify we have permission
        // If we don't have permission, window names will be empty
        for window in windows {
            if let windowName = window[kCGWindowName as String] as? String,
               !windowName.isEmpty {
                // If we can read window names, we have permission
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Permission Prompts
    
    func requestAccessibilityPermission() {
        // This will prompt the user to grant accessibility permission
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let hasPermission = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !hasPermission {
            print("PermissionsManager: Accessibility prompt shown. Please enable in System Settings.")
            print("Go to: System Settings → Privacy & Security → Accessibility")
            print("Then toggle ON the switch next to 'Hover-Dock'")
        }
        
        // Check again after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.checkPermissions()
            
            // Keep checking every 2 seconds until granted
            if !(self?.hasAccessibilityPermission ?? false) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self?.checkPermissions()
                }
            }
        }
    }
    
    func requestScreenRecordingPermission() {
        // Open System Settings to Screen Recording privacy pane
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        
        // Check again after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkPermissions()
        }
    }
    
    func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Status
    
    func hasAllRequiredPermissions() -> Bool {
        return hasAccessibilityPermission && hasScreenRecordingPermission
    }
    
    func getMissingPermissions() -> [String] {
        var missing: [String] = []
        
        if !hasAccessibilityPermission {
            missing.append("Accessibility")
        }
        
        if !hasScreenRecordingPermission {
            missing.append("Screen Recording")
        }
        
        return missing
    }
}
