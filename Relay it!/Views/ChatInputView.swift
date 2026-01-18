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

    @FocusState private var isInputFocused: Bool

    private var placeholder: String {
        if selectedCount > 0 {
            return "Ask about \(selectedCount) selected item\(selectedCount > 1 ? "s" : "")..."
        }
        return "Ask about your captures..."
    }

    var body: some View {
        VStack(spacing: 4) {
            // Selection hint - fixed height to prevent layout shift
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
            .opacity(selectedCount > 0 ? 1 : 0)
            .frame(height: selectedCount > 0 ? nil : 0)

            HStack(spacing: 12) {
                TextField(placeholder, text: $message)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color.themeText)
                    .padding(10)
                    .background(Color.themeInput)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .focused($isInputFocused)
                    .onSubmit {
                        if !message.isEmpty && !isLoading {
                            onSend()
                            // Maintain focus after sending
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isInputFocused = true
                            }
                        }
                    }

                Button(action: {
                    onSend()
                    // Maintain focus after sending
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isInputFocused = true
                    }
                }) {
                    ZStack {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(message.isEmpty ? Color.themeTextTertiary : Color.themeAccent)
                            .opacity(isLoading ? 0 : 1)

                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.themeAccent)
                        }
                    }
                    .frame(width: 28, height: 28)
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
