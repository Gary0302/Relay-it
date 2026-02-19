import SwiftUI

enum AICalloutQuickAction: String, CaseIterable, Identifiable {
    case summarizeScreenshots
    case fixGrammar
    case continueWriting
    case addComparisonTable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summarizeScreenshots:
            return "Summarize screenshots"
        case .fixGrammar:
            return "Fix grammar & spelling"
        case .continueWriting:
            return "Continue writing"
        case .addComparisonTable:
            return "Add comparison table"
        }
    }

    var icon: String {
        switch self {
        case .summarizeScreenshots:
            return "text.redaction"
        case .fixGrammar:
            return "checkmark.seal"
        case .continueWriting:
            return "text.append"
        case .addComparisonTable:
            return "tablecells"
        }
    }

    var defaultPrompt: String {
        switch self {
        case .summarizeScreenshots:
            return "Summarize my screenshots into a concise section and insert it here."
        case .fixGrammar:
            return "Fix grammar and spelling for this section and keep the same meaning."
        case .continueWriting:
            return "Continue writing this note in the same tone with the next useful paragraph."
        case .addComparisonTable:
            return "Add a markdown comparison table based on what is in this note and screenshots."
        }
    }
}

struct AICalloutPopup: View {
    @Binding var prompt: String
    let isLoading: Bool
    let errorMessage: String?
    let onSubmitPrompt: (String) -> Void
    let onQuickAction: (AICalloutQuickAction) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AI Assist")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.themeTextSecondary)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(Color.themeTextTertiary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                TextField("Ask AI...", text: $prompt)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .onSubmit {
                        onSubmitPrompt(prompt)
                    }

                Button(action: {
                    onSubmitPrompt(prompt)
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.themeTextTertiary : Color.themeAccent)
                }
                .buttonStyle(.plain)
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.themeBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.themeBorder, lineWidth: 1)
                    )
            )

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.red)
            }

            Divider()
                .background(Color.themeDivider)

            ForEach(AICalloutQuickAction.allCases) { action in
                Button(action: {
                    onQuickAction(action)
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: action.icon)
                            .font(.caption)
                            .foregroundStyle(Color.themeAccent)
                            .frame(width: 16)
                        Text(action.title)
                            .font(.subheadline)
                            .foregroundStyle(Color.themeText)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.themeBackground.opacity(0.001))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Generating...")
                        .font(.caption)
                        .foregroundStyle(Color.themeTextSecondary)
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.themeCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
        )
        .onExitCommand {
            onDismiss()
        }
    }
}
