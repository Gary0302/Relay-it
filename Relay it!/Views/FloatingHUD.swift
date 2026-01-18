//
//  FloatingHUD.swift
//  Relay it!
//
//  System-level floating notification HUD
//

import SwiftUI
import AppKit

/// Floating HUD notification that appears on screen (like "Copied Text!")
class FloatingHUD {
    static let shared = FloatingHUD()
    
    private var hudWindow: NSWindow?
    private var dismissTask: DispatchWorkItem?
    
    private init() {}
    
    /// Show a HUD notification on screen
    func show(message: String, icon: String = "checkmark", duration: TimeInterval = 1.5) {
        DispatchQueue.main.async { [weak self] in
            self?.dismissTask?.cancel()
            self?.hudWindow?.close()
            
            // Create HUD content
            let hudContent = HUDContentView(message: message, icon: icon)
            let hostingController = NSHostingController(rootView: hudContent)
            
            // Create floating window
            let window = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 160, height: 160),
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
            
            // Center on main screen (use frame for true center, not visibleFrame)
            if let screen = NSScreen.main {
                let screenFrame = screen.frame
                let windowSize = window.frame.size
                let x = screenFrame.origin.x + (screenFrame.width - windowSize.width) / 2
                let y = screenFrame.origin.y + (screenFrame.height - windowSize.height) / 2
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }
            
            // Show with animation
            window.alphaValue = 0
            window.orderFront(nil)
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                window.animator().alphaValue = 1
            }
            
            self?.hudWindow = window
            
            // Auto dismiss
            let dismissTask = DispatchWorkItem { [weak self] in
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.3
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

/// HUD content view
struct HUDContentView: View {
    let message: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(Color.themeAccent)

            Text(message)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.themeText)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 160, height: 160)
        .background(Color.themeCard)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.themeText.opacity(0.15), radius: 20, y: 10)
    }
}

#Preview {
    HUDContentView(message: "Captured!", icon: "checkmark")
        .padding()
}
