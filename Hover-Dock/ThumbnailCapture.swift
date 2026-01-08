//
//  ThumbnailCapture.swift
//  Hover-Dock
//
//  Created by Bramha Bajannavar on 30/12/25.
//

import Foundation
import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Manages window thumbnail capture and caching
class ThumbnailCapture: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var thumbnails: [CGWindowID: NSImage] = [:]
    @Published var isCapturing: Bool = false
    
    // MARK: - Private Properties
    
    private var captureCache: [CGWindowID: CachedThumbnail] = [:]
    private var captureQueue = DispatchQueue(label: "com.hoverdock.thumbnail", qos: .userInitiated)
    private var debounceTimers: [CGWindowID: Timer] = [:]
    
    // Cache entry
    private struct CachedThumbnail {
        let image: NSImage
        let captureTime: Date
        let windowBounds: CGRect
    }
    
    // Configuration
    private let thumbnailMaxWidth: CGFloat = 300
    private let thumbnailMaxHeight: CGFloat = 200
    private let cacheExpiration: TimeInterval = 5.0 // 5 seconds
    private let debounceDelay: TimeInterval = 0.3 // 300ms
    
    // MARK: - Public Methods
    
    /// Capture thumbnail for a specific window with debouncing
    func captureThumbnail(for windowInfo: WindowInfo, completion: ((NSImage?) -> Void)? = nil) {
        // Cancel existing timer for this window
        debounceTimers[windowInfo.id]?.invalidate()
        
        // Create debounced capture
        let timer = Timer.scheduledTimer(withTimeInterval: debounceDelay, repeats: false) { [weak self] _ in
            self?.performCapture(for: windowInfo, completion: completion)
        }
        
        debounceTimers[windowInfo.id] = timer
    }
    
    /// Capture thumbnails for multiple windows
    func captureThumbnails(for windows: [WindowInfo], completion: (([CGWindowID: NSImage]) -> Void)? = nil) {
        var results: [CGWindowID: NSImage] = [:]
        let group = DispatchGroup()
        
        for window in windows {
            group.enter()
            captureThumbnail(for: window) { image in
                if let image = image {
                    results[window.id] = image
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion?(results)
        }
    }
    
    /// Get cached thumbnail or trigger capture
    func getThumbnail(for windowInfo: WindowInfo) -> NSImage? {
        // Check cache first
        if let cached = captureCache[windowInfo.id] {
            // Check if cache is still valid
            let age = Date().timeIntervalSince(cached.captureTime)
            
            // Also check if window bounds changed (window resized)
            let boundsChanged = cached.windowBounds != windowInfo.bounds
            
            if age < cacheExpiration && !boundsChanged {
                return cached.image
            } else {
                // Cache expired or window resized, trigger recapture
                captureThumbnail(for: windowInfo)
            }
        } else {
            // Not in cache, trigger capture
            captureThumbnail(for: windowInfo)
        }
        
        return nil
    }
    
    /// Clear cache for specific window
    func clearCache(for windowID: CGWindowID) {
        captureCache.removeValue(forKey: windowID)
        thumbnails.removeValue(forKey: windowID)
    }
    
    /// Clear all cache
    func clearAllCache() {
        captureCache.removeAll()
        thumbnails.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func performCapture(for windowInfo: WindowInfo, completion: ((NSImage?) -> Void)?) {
        captureQueue.async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isCapturing = true
            }
            
            // Attempt to capture using ScreenCaptureKit (modern API for macOS 12.3+)
            self.captureUsingScreenCaptureKit(for: windowInfo) { image in
                if let image = image {
                    // Cache the thumbnail
                    let cached = CachedThumbnail(
                        image: image,
                        captureTime: Date(),
                        windowBounds: windowInfo.bounds
                    )
                    
                    self.captureCache[windowInfo.id] = cached
                    
                    DispatchQueue.main.async {
                        self.thumbnails[windowInfo.id] = image
                        self.isCapturing = false
                        completion?(image)
                    }
                } else {
                    // Fallback to legacy CGWindow API
                    self.captureUsingCGWindow(for: windowInfo, completion: completion)
                }
            }
        }
    }
    
    /// Modern capture using ScreenCaptureKit (macOS 12.3+)
    private func captureUsingScreenCaptureKit(for windowInfo: WindowInfo, completion: @escaping (NSImage?) -> Void) {
        if #available(macOS 12.3, *) {
            Task {
                do {
                    // Get available content
                    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                    
                    // Find the window by PID and title
                    guard let scWindow = content.windows.first(where: { window in
                        window.owningApplication?.processID == windowInfo.ownerPID &&
                        window.title == windowInfo.title
                    }) else {
                        print("ThumbnailCapture: Window not found in ScreenCaptureKit")
                        completion(nil)
                        return
                    }
                    
                    // Create content filter for this window
                    let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                    
                    // Configure capture
                    let config = SCStreamConfiguration()
                    config.width = Int(self.thumbnailMaxWidth * 2) // 2x for retina
                    config.height = Int(self.thumbnailMaxHeight * 2)
                    config.scalesToFit = true
                    config.showsCursor = false
                    
                    // Capture screenshot
                    guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else {
                        print("ThumbnailCapture: Failed to capture image for '\(windowInfo.title)'")
                        completion(nil)
                        return
                    }
                    
                    // Convert CGImage to NSImage
                    let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                    
                    // Resize to thumbnail size
                    let thumbnail = self.resizeImage(nsImage, maxWidth: self.thumbnailMaxWidth, maxHeight: self.thumbnailMaxHeight)
                    
                    print("ThumbnailCapture: ✅ Captured thumbnail for '\(windowInfo.title)' using ScreenCaptureKit")
                    completion(thumbnail)
                    
                } catch {
                    print("ThumbnailCapture: ScreenCaptureKit error: \(error.localizedDescription)")
                    completion(nil)
                }
            }
        } else {
            // macOS < 12.3
            completion(nil)
        }
    }
    
    /// Legacy capture using CGWindow API (deprecated in macOS 15, but still works)
    private func captureUsingCGWindow(for windowInfo: WindowInfo, completion: ((NSImage?) -> Void)?) {
        // CGWindowListCreateImage is deprecated in macOS 15+
        // This is a fallback that won't work on macOS 15+
        print("ThumbnailCapture: CGWindow API not available on macOS 15+")
        
        DispatchQueue.main.async {
            self.isCapturing = false
            completion?(nil)
        }
    }
    
    /// Resize image to fit within max dimensions while maintaining aspect ratio
    private func resizeImage(_ image: NSImage, maxWidth: CGFloat, maxHeight: CGFloat) -> NSImage {
        let originalSize = image.size
        
        // Calculate aspect ratio
        let widthRatio = maxWidth / originalSize.width
        let heightRatio = maxHeight / originalSize.height
        let ratio = min(widthRatio, heightRatio)
        
        // Calculate new size
        let newSize = NSSize(
            width: originalSize.width * ratio,
            height: originalSize.height * ratio
        )
        
        // Create resized image
        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()
        
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        
        resizedImage.unlockFocus()
        
        return resizedImage
    }
    
    // MARK: - Cleanup
    
    deinit {
        // Cancel all timers
        debounceTimers.values.forEach { $0.invalidate() }
        debounceTimers.removeAll()
    }
}
