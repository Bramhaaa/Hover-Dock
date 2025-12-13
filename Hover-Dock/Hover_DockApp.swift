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

    init() {
        let trusted = AXIsProcessTrusted()
        print("Accessibility trusted:", trusted)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
