//
//  ToastView.swift
//  Relay it!
//
//  Fade in/out toast notification
//

import SwiftUI

struct ToastView: View {
    let message: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .font(.title3)
            
            Text(message)
                .font(.callout.bold())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
    }
}

struct ToastModifier: ViewModifier {
    @Binding var isShowing: Bool
    let message: String
    let icon: String
    let duration: Double
    
    @State private var workItem: DispatchWorkItem?
    
    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            
            if isShowing {
                ToastView(message: message, icon: icon)
                    .padding(.top, 60)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .zIndex(999)
                    .onAppear {
                        // Cancel any existing work item
                        workItem?.cancel()
                        
                        // Create new work item to dismiss
                        let task = DispatchWorkItem {
                            withAnimation(.easeOut(duration: 0.3)) {
                                isShowing = false
                            }
                        }
                        workItem = task
                        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
                    }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isShowing)
    }
}

extension View {
    func toast(isShowing: Binding<Bool>, message: String, icon: String = "checkmark.circle.fill", duration: Double = 2.5) -> some View {
        modifier(ToastModifier(isShowing: isShowing, message: message, icon: icon, duration: duration))
    }
}

#Preview {
    VStack {
        Text("Content")
    }
    .frame(width: 400, height: 300)
    .toast(isShowing: .constant(true), message: "Capture successful!")
}
