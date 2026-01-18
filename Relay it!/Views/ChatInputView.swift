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
    let selectedCount: Int
    let onSend: () -> Void
    
    private var placeholder: String {
        if selectedCount > 0 {
            return "Ask about \(selectedCount) selected item\(selectedCount > 1 ? "s" : "")..."
        }
        return "Ask about your captures..."
    }
    
    var body: some View {
        VStack(spacing: 4) {
            // Selection hint
            if selectedCount > 0 {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.themeAccent)
                    Text("\(selectedCount) selected — questions will focus on these items")
                        .font(.caption)
                        .foregroundStyle(Color.themeTextSecondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }

            HStack(spacing: 12) {
                TextField(placeholder, text: $message)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color.themeText)
                    .padding(10)
                    .background(Color.themeInput)
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
                            .tint(Color.themeAccent)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(message.isEmpty ? Color.themeTextTertiary : Color.themeAccent)
                    }
                }
                .buttonStyle(.plain)
                .disabled(message.isEmpty || isLoading)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color.themeSurface)
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
                .background(isUser ? Color.themeAccent : Color.themeSurface)
                .foregroundStyle(isUser ? .white : Color.themeText)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if !isUser { Spacer() }
        }
    }
}

#Preview {
    VStack {
        ChatMessageView(isUser: true, message: "Which hotel has the best value?")
        ChatMessageView(isUser: false, message: "Based on your captures, the Marriott offers the best value with $199/night and 4.5 star rating.")
        ChatInputView(message: .constant(""), isLoading: false, selectedCount: 2, onSend: {})
    }
    .padding()
    .frame(width: 400)
}
