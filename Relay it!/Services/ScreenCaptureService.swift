//
//  ScreenCaptureService.swift
//  Relay it!
//
//  Created by Relay it! on 2026/1/17.
//

import Foundation
import ScreenCaptureKit
import AppKit
import Carbon.HIToolbox

/// Service for macOS screen capture
@MainActor
class ScreenCaptureService: ObservableObject {
    static let shared = ScreenCaptureService()
    
    @Published var isCapturing = false
    @Published var hasPermission = false
    
    private var hotkeyEventHandler: Any?
    
    private init() {
        checkPermission()
    }
    
    // MARK: - Permission
    
    /// Check if screen recording permission is granted
    func checkPermission() {
        // CGPreflightScreenCaptureAccess returns true if permission was previously granted
        hasPermission = CGPreflightScreenCaptureAccess()
    }
    
    /// Request screen recording permission
    func requestPermission() {
        // This will show the system permission dialog
        CGRequestScreenCaptureAccess()
        
        // Check again after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.checkPermission()
        }
    }
    
    // MARK: - Screenshot Capture
    
    /// Capture a region of the screen using screencapture command
    func captureRegion() async throws -> Data {
        isCapturing = true
        defer { isCapturing = false }
        
        // Create temporary file path
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("\(UUID().uuidString).png")
        
        // Use screencapture command with interactive mode (-i)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", tempFile.path]  // -i: interactive, -x: no sound
        
        try process.run()
        process.waitUntilExit()
        
        // Check if file was created (user completed capture)
        guard FileManager.default.fileExists(atPath: tempFile.path) else {
            throw ScreenCaptureError.captureAborted
        }
        
        // Read image data
        let imageData = try Data(contentsOf: tempFile)
        
        // Clean up temp file
        try? FileManager.default.removeItem(at: tempFile)
        
        guard !imageData.isEmpty else {
            throw ScreenCaptureError.emptyCapture
        }
        
        // Compress if too large (> 2MB for API calls)
        let maxSize = 2 * 1024 * 1024  // 2MB
        if imageData.count > maxSize {
            return compressImage(imageData, maxBytes: maxSize)
        }
        
        return imageData
    }
    
    /// Compress image to reduce file size for API calls
    private func compressImage(_ data: Data, maxBytes: Int) -> Data {
        guard let image = NSImage(data: data) else { return data }
        
        var quality: CGFloat = 0.8
        var compressionAttempts = 0
        var compressedData = data
        
        while compressedData.count > maxBytes && compressionAttempts < 5 {
            // Convert to JPEG with reduced quality
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
                break
            }
            
            compressedData = jpegData
            quality -= 0.15
            compressionAttempts += 1
        }
        
        // If still too large, resize the image
        if compressedData.count > maxBytes {
            let resizedImage = resizeImage(image, maxDimension: 1920)
            if let tiffData = resizedImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
                compressedData = jpegData
            }
        }
        
        print("Image compressed: \(data.count / 1024)KB -> \(compressedData.count / 1024)KB")
        return compressedData
    }
    
    /// Resize image to max dimension while maintaining aspect ratio
    private func resizeImage(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let originalSize = image.size
        var newSize = originalSize
        
        if originalSize.width > maxDimension || originalSize.height > maxDimension {
            if originalSize.width > originalSize.height {
                newSize.width = maxDimension
                newSize.height = (originalSize.height / originalSize.width) * maxDimension
            } else {
                newSize.height = maxDimension
                newSize.width = (originalSize.width / originalSize.height) * maxDimension
            }
        }
        
        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: originalSize),
                   operation: .copy,
                   fraction: 1.0)
        resizedImage.unlockFocus()
        
        return resizedImage
    }
    
    /// Capture entire screen (for testing)
    func captureScreen() async throws -> Data {
        isCapturing = true
        defer { isCapturing = false }
        
        guard hasPermission else {
            throw ScreenCaptureError.permissionDenied
        }
        
        // Get shareable content
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        
        guard let display = content.displays.first else {
            throw ScreenCaptureError.noDisplay
        }
        
        // Configure capture
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        
        // Capture screenshot
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        
        // Convert to PNG data
        guard let data = image.pngData() else {
            throw ScreenCaptureError.conversionFailed
        }
        
        return data
    }
    
    // MARK: - Global Hotkey
    
    typealias HotkeyHandler = () -> Void
    private var hotkeyCallback: HotkeyHandler?
    
    /// Register global hotkey (Cmd+Shift+E)
    func registerHotkey(handler: @escaping HotkeyHandler) {
        hotkeyCallback = handler
        
        // Register event tap for global key monitoring
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard type == .keyDown else {
                    return Unmanaged.passRetained(event)
                }
                
                let flags = event.flags
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                
                // Check for Cmd+Shift+E (keyCode 14 = E)
                let isCmd = flags.contains(.maskCommand)
                let isShift = flags.contains(.maskShift)
                let isE = keyCode == 14
                
                if isCmd && isShift && isE {
                    // Get the service instance from refcon
                    if let refcon = refcon {
                        let service = Unmanaged<ScreenCaptureService>.fromOpaque(refcon).takeUnretainedValue()
                        DispatchQueue.main.async {
                            service.hotkeyCallback?()
                        }
                    }
                    return nil  // Consume the event
                }
                
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Failed to create event tap")
            return
        }
        
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        hotkeyEventHandler = eventTap
    }
    
    /// Unregister global hotkey
    func unregisterHotkey() {
        hotkeyCallback = nil
        hotkeyEventHandler = nil
    }
}

// MARK: - CGImage Extension
extension CGImage {
    func pngData() -> Data? {
        guard let mutableData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil) else {
            return nil
        }
        
        CGImageDestinationAddImage(destination, self, nil)
        
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        
        return mutableData as Data
    }
}

// MARK: - Errors
enum ScreenCaptureError: LocalizedError {
    case permissionDenied
    case noDisplay
    case captureAborted
    case emptyCapture
    case conversionFailed
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen recording permission is required"
        case .noDisplay:
            return "No display found"
        case .captureAborted:
            return "Screenshot capture was cancelled"
        case .emptyCapture:
            return "Captured image is empty"
        case .conversionFailed:
            return "Failed to convert image"
        }
    }
}
