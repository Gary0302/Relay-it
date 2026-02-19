//
//  ChatPanel.swift
//  Relay it!
//
//  Notion-style main note editor with inline AI callout
//

import SwiftUI

struct ChatPanel: View {
    @ObservedObject var appState: AppState
    @ObservedObject var viewModel: SessionViewModel
    @Binding var selectedScreenshotId: UUID?

    @State private var showPreview = false
    @State private var activeCommand: NoteEditorCommand?
    @State private var commandNonce = 0

    @State private var showAICallout = false
    @State private var aiCalloutAnchor = CGPoint(x: 180, y: 160)
    @State private var aiPromptText = ""
    @State private var isAICallRunning = false
    @State private var aiCalloutError: String?

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                editorView

                if let hint = viewModel.aiSuggestionHint {
                    aiHintBubble(hint)
                }

                if showAICallout {
                    calloutOverlay
                }
            }

            Divider()
                .background(Color.themeDivider)

            bottomToolbar
        }
        .background(Color.themeBackground)
        .onDisappear {
            Task { await viewModel.saveNote() }
        }
    }

    private var editorView: some View {
        Group {
            if viewModel.isLoading {
                VStack {
                    Spacer()
                    ProgressView("Loading note...")
                        .tint(Color.themeAccent)
                    Spacer()
                }
            } else {
                NoteEditorView(
                    content: $viewModel.noteContent,
                    showPreview: $showPreview,
                    isSaving: viewModel.isNoteSaving,
                    aiHighlightActive: viewModel.aiHighlightActive,
                    aiHighlightStartIndex: viewModel.aiHighlightStartIndex,
                    showsToolbar: false,
                    command: activeCommand,
                    commandNonce: commandNonce,
                    onSpaceOnEmptyLine: { point in
                        aiCalloutAnchor = point
                        aiPromptText = ""
                        aiCalloutError = nil
                        showAICallout = true
                    },
                    onCursorChange: { index, anchor in
                        viewModel.updateCursorPosition(index: index, anchor: anchor)
                    },
                    onAnyKeyPress: {
                        viewModel.dismissAISuggestionHint()
                    }
                )
            }
        }
    }

    private var bottomToolbar: some View {
        HStack(spacing: 12) {
            toolbarButton("bold", command: .bold)
            toolbarButton("italic", command: .italic)
            toolbarButton("textformat.size.larger", command: .h1)
            toolbarButton("textformat.size", command: .h2)
            toolbarButton("list.bullet", command: .bullet)
            toolbarButton("list.number", command: .numbered)
            toolbarButton("text.quote", command: .quote)
            toolbarButton("minus", command: .divider)

            Divider()
                .frame(height: 16)

            Button(action: { showPreview.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: showPreview ? "eye.fill" : "eye")
                    Text("Preview")
                        .font(.caption)
                }
                .foregroundStyle(showPreview ? Color.themeAccent : Color.themeTextSecondary)
            }
            .buttonStyle(.plain)
            .help(showPreview ? "Hide preview" : "Show preview")

            Spacer()

            HStack(spacing: 6) {
                if isAICallRunning {
                    ProgressView()
                        .scaleEffect(0.6)
                }

                if viewModel.isNoteSaving {
                    Text("Saving...")
                        .font(.caption)
                        .foregroundStyle(Color.themeTextSecondary)
                } else if isAICallRunning {
                    Text("AI writing...")
                        .font(.caption)
                        .foregroundStyle(Color.themeTextSecondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.themeSurface)
    }

    private func toolbarButton(_ icon: String, command: NoteEditorCommand) -> some View {
        Button(action: { runCommand(command) }) {
            Image(systemName: icon)
                .foregroundStyle(Color.themeTextSecondary)
        }
        .buttonStyle(.plain)
    }

    private func runCommand(_ command: NoteEditorCommand) {
        activeCommand = command
        commandNonce += 1
    }

    private var calloutOverlay: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissCallout() }

            AICalloutPopup(
                prompt: $aiPromptText,
                isLoading: isAICallRunning,
                errorMessage: aiCalloutError,
                onSubmitPrompt: { submitAIPrompt($0) },
                onQuickAction: { action in
                    submitAIPrompt(action.defaultPrompt)
                },
                onDismiss: { dismissCallout() }
            )
            .frame(width: 320)
            .position(x: aiCalloutAnchor.x + 160, y: aiCalloutAnchor.y + 92)
        }
    }

    private func aiHintBubble(_ hint: String) -> some View {
        Text("AI: \(hint)")
            .font(.caption)
            .foregroundStyle(Color.themeTextSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.themeCard.opacity(0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.themeBorder, lineWidth: 1)
                    )
            )
            .position(x: viewModel.cursorAnchor.x + 130, y: max(16, viewModel.cursorAnchor.y + 22))
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .animation(.easeInOut(duration: 0.15), value: hint)
    }

    private func submitAIPrompt(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isAICallRunning = true
        aiCalloutError = nil

        Task {
            do {
                try await viewModel.runInlineAICallout(prompt: trimmed)
                await MainActor.run {
                    isAICallRunning = false
                    showAICallout = false
                }
            } catch {
                await MainActor.run {
                    isAICallRunning = false
                    aiCalloutError = error.localizedDescription
                }
            }
        }
    }

    private func dismissCallout() {
        guard !isAICallRunning else { return }
        showAICallout = false
        aiCalloutError = nil
    }
}

#Preview {
    ChatPanel(
        appState: AppState.shared,
        viewModel: SessionViewModel(sessionId: UUID()),
        selectedScreenshotId: .constant(nil)
    )
    .frame(width: 700, height: 700)
}
