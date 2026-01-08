//
//  ContentView.swift
//  Hover-Dock
//
//  Created by Bramha Bajannavar on 13/12/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var permissionsManager: PermissionsManager
    @EnvironmentObject var dockIconDetector: DockIconDetector
    @EnvironmentObject var windowDiscovery: WindowDiscovery
    @EnvironmentObject var thumbnailCapture: ThumbnailCapture
    @EnvironmentObject var previewOverlay: PreviewOverlayController
    
    var body: some View {
        VStack(spacing: 20) {
            // App Icon
            Image(systemName: "dock.rectangle")
                .font(.system(size: 60))
                .foregroundStyle(dockIconDetector.hoveredApp != nil ? .green : .gray)
            
            // App Title
            Text("HoverDock")
                .font(.title)
                .fontWeight(.bold)
            
            // Permissions Status
            if !permissionsManager.hasAllRequiredPermissions() {
                VStack(spacing: 12) {
                    Text("⚠️ Missing Permissions")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        if !permissionsManager.hasAccessibilityPermission {
                            HStack {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.red)
                                Text("Accessibility")
                                Spacer()
                                Button("Grant") {
                                    permissionsManager.requestAccessibilityPermission()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        
                        if !permissionsManager.hasScreenRecordingPermission {
                            HStack {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.red)
                                Text("Screen Recording")
                                Spacer()
                                Button("Grant") {
                                    permissionsManager.requestScreenRecordingPermission()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Divider()
            }
            
            // Status
            VStack(spacing: 8) {
                let dockPosition = DockUtils.getDockPosition()
                Text("Dock Position: \(dockPosition.displayName)")
                    .font(.headline)
                
                Text(dockIconDetector.hoveredApp != nil ? "🟢 Hovering Dock Icon" : "⚪️ Not Hovering")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(dockIconDetector.hoveredApp != nil ? .green : .secondary)
                
                // Show hovered app
                if let app = dockIconDetector.hoveredApp {
                    Text("Hovering: \(app.localizedName ?? "Unknown")")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .padding(.top, 4)
                    
                    // Show window count and preview status
                    let windows = windowDiscovery.discoveredWindows
                    if !windows.isEmpty {
                        Text("\(windows.count) window(s)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        if previewOverlay.isVisible {
                            Text("Preview: Showing")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                    
                    // Capture thumbnails for testing
                    if thumbnailCapture.isCapturing {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
                }
            }
            
            Divider()
                .padding(.horizontal)
            
            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                Text("Status: \(permissionsManager.hasAllRequiredPermissions() ? "Active" : "Waiting for permissions")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("Move your mouse over the Dock to test detection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(30)
        .frame(minWidth: 400, minHeight: 400)
        .onAppear {
            setupPreviewOverlay()
        }
        .onChange(of: dockIconDetector.hoveredApp) { oldValue, newValue in
            handleHoveredAppChange(newValue)
        }
    }
    
    private func setupPreviewOverlay() {
        // Set up callbacks
        previewOverlay.onWindowFocus = { windowInfo in
            windowDiscovery.focusWindow(windowInfo)
        }
        
        previewOverlay.onWindowClose = { windowInfo in
            windowDiscovery.closeWindow(windowInfo)
        }
        
        previewOverlay.onWindowMinimize = { windowInfo in
            windowDiscovery.minimizeWindow(windowInfo)
        }
    }
    
    private func handleHoveredAppChange(_ app: NSRunningApplication?) {
        guard let app = app else {
            previewOverlay.hide()
            return
        }
        
        // Capture the icon center NOW (before async operations)
        let capturedIconCenter = dockIconDetector.hoveredIconCenter
        
        // Discover windows for the app
        let windows = windowDiscovery.discoverWindows(for: app)
        
        guard !windows.isEmpty else {
            previewOverlay.hide()
            return
        }
        
        // Capture thumbnails
        thumbnailCapture.captureThumbnails(for: windows) { [self] capturedThumbnails in
            // Show preview overlay with thumbnails at the captured icon position
            previewOverlay.show(for: app, windows: windows, thumbnails: capturedThumbnails, iconCenter: capturedIconCenter)
        }
    }
}

#Preview {
    ContentView()
}
