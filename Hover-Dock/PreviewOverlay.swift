//
//  PreviewOverlay.swift
//  Hover-Dock
//
//  Created by Bramha Bajannavar on 31/12/25.
//

import Foundation
import AppKit
import SwiftUI

/// Manages the floating preview overlay window
class PreviewOverlayController: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isVisible: Bool = false
    @Published var windows: [WindowInfo] = []
    @Published var thumbnails: [CGWindowID: NSImage] = [:]
    
    // MARK: - Private Properties
    
    private var overlayWindow: NSPanel?
    private var currentApp: NSRunningApplication?
    private var iconCenter: CGPoint?  // Center of the hovered icon
    
    // Configuration
    private let thumbnailWidth: CGFloat = 200
    private let thumbnailHeight: CGFloat = 150
    private let thumbnailSpacing: CGFloat = 12
    private let overlayPadding: CGFloat = 16
    private let overlayOffset: CGFloat = 10 // Distance from Dock edge
    
    // MARK: - Callbacks
    
    var onWindowFocus: ((WindowInfo) -> Void)?
    var onWindowClose: ((WindowInfo) -> Void)?
    var onWindowMinimize: ((WindowInfo) -> Void)?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Show preview overlay for app windows
    func show(for app: NSRunningApplication, windows: [WindowInfo], thumbnails: [CGWindowID: NSImage], iconCenter: CGPoint?) {
        guard !windows.isEmpty else {
            hide()
            return
        }
        
        self.currentApp = app
        self.windows = windows
        self.thumbnails = thumbnails
        self.iconCenter = iconCenter
        
        // Filter to only windows with thumbnails
        let validWindows = windows.filter { thumbnails[$0.id] != nil }
        guard !validWindows.isEmpty else {
            hide()
            return
        }
        
        // Create or update overlay window
        if overlayWindow == nil {
            createOverlayWindow()
        }
        
        updateOverlayContent()
        positionOverlay()
        
        overlayWindow?.orderFrontRegardless()
        isVisible = true
        
        print("PreviewOverlay: Showing \(windows.count) window(s) for \(app.localizedName ?? "app") at icon: \(iconCenter?.debugDescription ?? "nil")")
    }
    
    /// Hide preview overlay
    func hide() {
        overlayWindow?.orderOut(nil)
        isVisible = false
        windows.removeAll()
        thumbnails.removeAll()
        currentApp = nil
        
        print("PreviewOverlay: Hidden")
    }
    
    /// Update overlay position (when Dock position changes or mouse moves)
    func updatePosition() {
        positionOverlay()
    }
    
    // MARK: - Private Methods
    
    private func createOverlayWindow() {
        // Create borderless, floating panel
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        
        panel.level = .popUpMenu // Higher than normal windows
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        
        // Set content view
        let hostingView = NSHostingView(rootView: PreviewOverlayView(
            windows: windows,
            thumbnails: thumbnails,
            thumbnailWidth: thumbnailWidth,
            thumbnailHeight: thumbnailHeight,
            onWindowClick: { [weak self] windowInfo in
                self?.handleWindowClick(windowInfo)
            },
            onCloseClick: { [weak self] windowInfo in
                self?.handleCloseClick(windowInfo)
            },
            onMinimizeClick: { [weak self] windowInfo in
                self?.handleMinimizeClick(windowInfo)
            }
        ))
        
        panel.contentView = hostingView
        
        overlayWindow = panel
    }
    
    private func updateOverlayContent() {
        guard let panel = overlayWindow else { return }
        
        // Update hosting view with new data
        let hostingView = NSHostingView(rootView: PreviewOverlayView(
            windows: windows,
            thumbnails: thumbnails,
            thumbnailWidth: thumbnailWidth,
            thumbnailHeight: thumbnailHeight,
            onWindowClick: { [weak self] windowInfo in
                self?.handleWindowClick(windowInfo)
            },
            onCloseClick: { [weak self] windowInfo in
                self?.handleCloseClick(windowInfo)
            },
            onMinimizeClick: { [weak self] windowInfo in
                self?.handleMinimizeClick(windowInfo)
            }
        ))
        
        panel.contentView = hostingView
        
        // Calculate window size based on content
        let overlaySize = calculateOverlaySize()
        panel.setContentSize(overlaySize)
    }
    
    private func calculateOverlaySize() -> NSSize {
        let dockPosition = DockUtils.getDockPosition()
        let windowCount = windows.count
        
        switch dockPosition {
        case .top, .bottom:
            // Horizontal layout
            let width = CGFloat(windowCount) * thumbnailWidth + CGFloat(windowCount - 1) * thumbnailSpacing + overlayPadding * 2
            let height = thumbnailHeight + overlayPadding * 2 + 30 // Extra for title
            return NSSize(width: width, height: height)
            
        case .left, .right:
            // Vertical layout
            let width = thumbnailWidth + overlayPadding * 2
            let height = CGFloat(windowCount) * thumbnailHeight + CGFloat(windowCount - 1) * thumbnailSpacing + overlayPadding * 2 + 30
            return NSSize(width: width, height: height)
            
        case .unknown:
            // Default to horizontal layout
            let width = CGFloat(windowCount) * thumbnailWidth + CGFloat(windowCount - 1) * thumbnailSpacing + overlayPadding * 2
            let height = thumbnailHeight + overlayPadding * 2 + 30
            return NSSize(width: width, height: height)
        }
    }
    
    private func positionOverlay() {
        guard let panel = overlayWindow,
              let screen = NSScreen.main else {
            return
        }
        
        let dockPosition = DockUtils.getDockPosition()
        let screenFrame = screen.frame
        let panelSize = panel.frame.size
        
        // Always use current mouse position for stable positioning
        let mouseLocation = NSEvent.mouseLocation
        
        var origin: NSPoint
        
        switch dockPosition {
        case .top:
            // Position below Dock, centered on mouse X position
            let x = mouseLocation.x - (panelSize.width / 2)
            let y = screenFrame.maxY - 80 - overlayOffset - panelSize.height // 80 = approximate Dock height
            
            // Keep within screen bounds
            let clampedX = max(screenFrame.minX, min(x, screenFrame.maxX - panelSize.width))
            origin = NSPoint(x: clampedX, y: y)
            
        case .bottom:
            // Position above Dock, centered on mouse X position
            let x = mouseLocation.x - (panelSize.width / 2)
            let y = screenFrame.minY + 80 + overlayOffset // 80 = approximate Dock height
            
            // Keep within screen bounds
            let clampedX = max(screenFrame.minX, min(x, screenFrame.maxX - panelSize.width))
            origin = NSPoint(x: clampedX, y: y)
            
        case .left:
            // Position to the right of Dock, centered on mouse Y position (stable!)
            let x = screenFrame.minX + 80 + overlayOffset
            let y = mouseLocation.y - (panelSize.height / 2)
            
            let clampedY = max(screenFrame.minY, min(y, screenFrame.maxY - panelSize.height))
            origin = NSPoint(x: x, y: clampedY)
            
            NSLog("PreviewOverlay: LEFT Dock positioning:")
            NSLog("  Mouse: \(mouseLocation)")
            NSLog("  Screen: \(screenFrame)")
            NSLog("  Panel size: \(panelSize)")
            NSLog("  Calculated X: \(x), Y: \(y)")
            NSLog("  Final origin: \(origin)")
            
        case .right:
            // Position to the left of Dock, centered on mouse Y position
            let x = screenFrame.maxX - 80 - overlayOffset - panelSize.width
            let y = mouseLocation.y - (panelSize.height / 2)
            
            let clampedY = max(screenFrame.minY, min(y, screenFrame.maxY - panelSize.height))
            origin = NSPoint(x: x, y: clampedY)
            
        case .unknown:
            // Default to bottom position
            let x = mouseLocation.x - (panelSize.width / 2)
            let y = screenFrame.minY + 80 + overlayOffset
            let clampedX = max(screenFrame.minX, min(x, screenFrame.maxX - panelSize.width))
            origin = NSPoint(x: clampedX, y: y)
        }
        
        panel.setFrameOrigin(origin)
    }
    
    private func handleWindowClick(_ windowInfo: WindowInfo) {
        print("PreviewOverlay: Window clicked: \(windowInfo.title)")
        onWindowFocus?(windowInfo)
        hide()
    }
    
    private func handleCloseClick(_ windowInfo: WindowInfo) {
        print("PreviewOverlay: Close clicked: \(windowInfo.title)")
        onWindowClose?(windowInfo)
        
        // Remove from current windows
        windows.removeAll { $0.id == windowInfo.id }
        thumbnails.removeValue(forKey: windowInfo.id)
        
        // Hide if no more windows
        if windows.isEmpty {
            hide()
        } else {
            updateOverlayContent()
            positionOverlay()
        }
    }
    
    private func handleMinimizeClick(_ windowInfo: WindowInfo) {
        print("PreviewOverlay: Minimize clicked: \(windowInfo.title)")
        onWindowMinimize?(windowInfo)
        
        // Remove from current windows
        windows.removeAll { $0.id == windowInfo.id }
        thumbnails.removeValue(forKey: windowInfo.id)
        
        // Hide if no more windows
        if windows.isEmpty {
            hide()
        } else {
            updateOverlayContent()
            positionOverlay()
        }
    }
}

// MARK: - SwiftUI Preview Overlay View

struct PreviewOverlayView: View {
    let windows: [WindowInfo]
    let thumbnails: [CGWindowID: NSImage]
    let thumbnailWidth: CGFloat
    let thumbnailHeight: CGFloat
    let onWindowClick: (WindowInfo) -> Void
    let onCloseClick: (WindowInfo) -> Void
    let onMinimizeClick: (WindowInfo) -> Void
    
    @State private var hoveredWindowID: CGWindowID?
    
    var body: some View {
        let dockPosition = DockUtils.getDockPosition()
        let isVerticalDock = dockPosition == .left || dockPosition == .right
        let validWindows = windows.filter { thumbnails[$0.id] != nil }
        
        return ZStack {
            // Background with blur
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            
            // Content
            VStack(spacing: 12) {
                // Thumbnail grid - only show windows with thumbnails
                if !validWindows.isEmpty {
                    if isVerticalDock {
                        // Vertical layout for left/right dock
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 12) {
                                ForEach(validWindows) { window in
                                ThumbnailPreview(
                                    window: window,
                                    thumbnail: thumbnails[window.id],
                                    width: thumbnailWidth,
                                    height: thumbnailHeight,
                                    isHovered: hoveredWindowID == window.id,
                                    onHover: { isHovered in
                                        hoveredWindowID = isHovered ? window.id : nil
                                    },
                                    onClick: {
                                        onWindowClick(window)
                                    },
                                    onClose: {
                                        onCloseClick(window)
                                    },
                                    onMinimize: {
                                        onMinimizeClick(window)
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 16)
                    }
                    } else {
                        // Horizontal layout for top/bottom dock
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(validWindows) { window in
                                ThumbnailPreview(
                                    window: window,
                                    thumbnail: thumbnails[window.id],
                                    width: thumbnailWidth,
                                    height: thumbnailHeight,
                                    isHovered: hoveredWindowID == window.id,
                                    onHover: { isHovered in
                                        hoveredWindowID = isHovered ? window.id : nil
                                    },
                                    onClick: {
                                        onWindowClick(window)
                                    },
                                    onClose: {
                                        onCloseClick(window)
                                    },
                                    onMinimize: {
                                        onMinimizeClick(window)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Thumbnail Preview Card

struct ThumbnailPreview: View {
    let window: WindowInfo
    let thumbnail: NSImage?
    let width: CGFloat
    let height: CGFloat
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let onClick: () -> Void
    let onClose: () -> Void
    let onMinimize: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                // Thumbnail or placeholder
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: width, height: height)
                        .cornerRadius(8)
                } else {
                    // Placeholder
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: width, height: height)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.white.opacity(0.5))
                        )
                }
                
                // Close button (shown on hover)
                if isHovered {
                    HStack(spacing: 4) {
                        // Minimize button (orange)
                        Button(action: {
                            onMinimize()
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .background(
                                    Circle()
                                        .fill(Color.orange)
                                        .blur(radius: 2)
                                )
                        }
                        .buttonStyle(.plain)
                        
                        // Close button (red)
                        Button(action: {
                            onClose()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .background(
                                    Circle()
                                        .fill(Color.red)
                                        .blur(radius: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovered ? Color.white : Color.clear, lineWidth: 2)
            )
            
            // Window title
            Text(window.title.isEmpty ? window.ownerName : window.title)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(maxWidth: width)
        }
        .onHover { hovering in
            onHover(hovering)
        }
        .onTapGesture {
            onClick()
        }
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
    }
}

// MARK: - Visual Effect View (NSVisualEffectView wrapper)

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
