//
//  ChatInputView.swift
//  Relay it!
//
//  Chat input for asking questions about the session
//

import SwiftUI

struct ChatInputView: View {
    @Binding var message: String
    let isLoading: Bool
    let onSend: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            TextField("Ask about your captures...", text: $message)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onSubmit {
                    if !message.isEmpty && !isLoading {
                        onSend()
                    }
                }
            
            Button(action: onSend) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(message.isEmpty ? Color.secondary : Color.blue)
                }
            }
            .buttonStyle(.plain)
            .disabled(message.isEmpty || isLoading)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ChatMessageView: View {
    let isUser: Bool
    let message: String
    
    var body: some View {
        HStack {
            if isUser { Spacer() }
            
            Text(message)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isUser ? Color.blue : Color.secondary.opacity(0.2))
                .foregroundStyle(isUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            if !isUser { Spacer() }
        }
    }
}

#Preview {
    VStack {
        ChatMessageView(isUser: true, message: "Which hotel has the best value?")
        ChatMessageView(isUser: false, message: "Based on your captures, the Marriott offers the best value with $199/night and 4.5 star rating.")
        ChatInputView(message: .constant(""), isLoading: false, onSend: {})
    }
    .padding()
    .frame(width: 400)
}
