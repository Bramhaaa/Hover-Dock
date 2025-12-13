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
    
    @StateObject private var dockDetector = DockDetector()

    init() {
        // Check Accessibility permission
        let trusted = AXIsProcessTrusted()
        print("Accessibility trusted:", trusted)
        
        if !trusted {
            print("⚠️ HoverDock requires Accessibility permission to function.")
            print("Please grant permission in System Settings > Privacy & Security > Accessibility")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dockDetector)
        }
    }
}
