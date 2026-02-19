//
//  ChatInputView.swift
//  Relay it!
//
//  ChatGPT-style input bar with attachment support
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
        return "Message Relay it!..."
    }

    var body: some View {
        VStack(spacing: 0) {
            // Selection hint
            if selectedCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.themeAccent)
                    Text("\(selectedCount) item\(selectedCount > 1 ? "s" : "") selected")
                        .font(.caption)
                        .foregroundStyle(Color.themeTextSecondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 2)
            }
            
            // Input row
            HStack(alignment: .bottom, spacing: 10) {
                // Text input with rounded border
                HStack(alignment: .bottom, spacing: 8) {
                    TextField(placeholder, text: $message, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .foregroundStyle(Color.themeText)
                        .lineLimit(1...6)
                        .focused($isInputFocused)
                        .onSubmit {
                            if !message.isEmpty && !isLoading {
                                onSend()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    isInputFocused = true
                                }
                            }
                        }
                    
                    // Send button inside the input field
                    Button(action: {
                        onSend()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isInputFocused = true
                        }
                    }) {
                        ZStack {
                            if isLoading {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(Color.themeAccent)
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(
                                        message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                            ? Color.themeTextTertiary
                                            : Color.themeAccent
                                    )
                            }
                        }
                        .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.themeInput)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isInputFocused ? Color.themeAccent.opacity(0.4) : Color.themeBorder.opacity(0.5), lineWidth: 1)
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.themeBackground)
    }
}

#Preview {
    VStack {
        Spacer()
        ChatInputView(message: .constant(""), isLoading: false, selectedCount: 0, onSend: {})
        ChatInputView(message: .constant("Hello there"), isLoading: false, selectedCount: 2, onSend: {})
        ChatInputView(message: .constant(""), isLoading: true, selectedCount: 0, onSend: {})
    }
    .frame(width: 500, height: 400)
    .background(Color.themeBackground)
}
