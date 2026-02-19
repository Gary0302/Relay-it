//
//  FloatingHUD.swift
//  Relay it!
//
//  System-level floating notification HUD (used only for screenshot capture)
//

import SwiftUI
import AppKit

/// Floating HUD notification that appears on screen (for out-of-app actions like capture)
class FloatingHUD {
    static let shared = FloatingHUD()
    
    private var hudWindow: NSWindow?
    private var dismissTask: DispatchWorkItem?
    
    private init() {}
    
    /// Show a HUD notification centered on the app's key window (or screen center as fallback)
    func show(message: String, icon: String = "checkmark", duration: TimeInterval = 1.2) {
        DispatchQueue.main.async { [weak self] in
            self?.dismissTask?.cancel()
            self?.hudWindow?.close()
            
            let hudSize = CGSize(width: 140, height: 140)
            let hudContent = HUDContentView(message: message, icon: icon)
            let hostingController = NSHostingController(rootView: hudContent)
            
            let window = NSPanel(
                contentRect: NSRect(origin: .zero, size: hudSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            
            window.contentViewController = hostingController
            window.backgroundColor = .clear
            window.isOpaque = false
            window.level = .floating
            window.hasShadow = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.ignoresMouseEvents = true
            
            // Find the reference frame to center within
            let referenceFrame: NSRect
            if let appWindow = NSApp.keyWindow ?? NSApp.mainWindow {
                referenceFrame = appWindow.frame
            } else if let screen = NSScreen.main {
                referenceFrame = screen.visibleFrame
            } else {
                referenceFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
            }
            
            // Calculate center of reference frame, then offset by half the HUD size
            let centerX = referenceFrame.midX - hudSize.width / 2
            let centerY = referenceFrame.midY - hudSize.height / 2
            window.setFrameOrigin(NSPoint(x: centerX, y: centerY))
            
            window.alphaValue = 0
            window.orderFront(nil)
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                window.animator().alphaValue = 1
            }
            
            self?.hudWindow = window
            
            let dismissTask = DispatchWorkItem { [weak self] in
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.25
                    self?.hudWindow?.animator().alphaValue = 0
                }, completionHandler: {
                    self?.hudWindow?.close()
                    self?.hudWindow = nil
                })
            }
            self?.dismissTask = dismissTask
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: dismissTask)
        }
    }
}

/// HUD content view -- uses app's light theme, no dark material
struct HUDContentView: View {
    let message: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(Color.themeAccent.opacity(0.65))

            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.themeText)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(width: 140, height: 140)
        .background(Color.themeCard.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.themeText.opacity(0.08), radius: 16, y: 6)
    }
}

#Preview {
    HUDContentView(message: "Captured!", icon: "checkmark")
        .padding()
}
