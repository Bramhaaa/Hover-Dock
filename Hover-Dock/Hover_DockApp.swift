//
//  Hover_DockApp.swift
//  Hover-Dock
//
//  Created by Bramha Bajannavar on 13/12/25.
//


import SwiftUI
import ApplicationServices

@main
struct Hover_DockApp: App {
    
    @StateObject private var permissionsManager = PermissionsManager.shared
    @StateObject private var dockIconDetector = DockIconDetector()
    @StateObject private var windowDiscovery = WindowDiscovery()
    @StateObject private var thumbnailCapture = ThumbnailCapture()
    @StateObject private var previewOverlay: PreviewOverlayController

    init() {
        // Initialize preview overlay without DockDetector
        let overlay = PreviewOverlayController()
        _previewOverlay = StateObject(wrappedValue: overlay)
        
        // IMMEDIATELY trigger accessibility permission prompt
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let hasAccessibility = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        print("Permissions Status:")
        print("  Accessibility: \(hasAccessibility ? "✅" : "❌")")
        
        if !hasAccessibility {
            print("⚠️ Accessibility permission prompt should appear now!")
            print("If not, please manually add this app in:")
            print("System Settings → Privacy & Security → Accessibility")
        }
        
        // Check all permissions
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            PermissionsManager.shared.checkPermissions()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(permissionsManager)
                .environmentObject(dockIconDetector)
                .environmentObject(windowDiscovery)
                .environmentObject(thumbnailCapture)
                .environmentObject(previewOverlay)
        }
    }
}
