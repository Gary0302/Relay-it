//
//  NoteEditorView.swift
//  Relay it!
//
//  Rich text editor with markdown preview for session notes
//

import SwiftUI

struct NoteEditorView: View {
    @Binding var content: String
    @State private var showPreview = false
    var isSaving: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with format buttons
            HStack {
                // Saving indicator
                if isSaving {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Saving...")
                            .font(.caption)
                            .foregroundStyle(Color.themeTextSecondary)
                    }
                }
                
                Spacer()
                
                // Format buttons
                HStack(spacing: 8) {
                    FormatButton(icon: "bold", action: { insertMarkdown("**", "**") })
                    FormatButton(icon: "italic", action: { insertMarkdown("*", "*") })
                    FormatButton(icon: "list.bullet", action: { insertMarkdown("- ", "") })
                    FormatButton(icon: "number", action: { insertMarkdown("1. ", "") })
                    
                    Divider()
                        .frame(height: 16)
                    
                    // Preview toggle
                    Button(action: { showPreview.toggle() }) {
                        Image(systemName: showPreview ? "eye.fill" : "eye")
                            .foregroundStyle(showPreview ? Color.themeAccent : Color.themeTextSecondary)
                    }
                    .buttonStyle(.plain)
                    .help(showPreview ? "Hide Preview" : "Show Preview")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.themeSurface)
            
            Divider()
            
            // Editor / Preview
            if showPreview {
                // Split view: Editor + Preview
                HSplitView {
                    editorPane
                    previewPane
                }
            } else {
                // Editor only
                editorPane
            }
        }
        .background(Color.themeBackground)
    }
    
    private var editorPane: some View {
        TextEditor(text: $content)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(Color.themeText)
            .scrollContentBackground(.hidden)
            .padding(16)
            .background(Color.themeBackground)
    }
    
    private var previewPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MarkdownView(content: content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            }
            .padding(16)
        }
        .background(Color.themeSurface)
    }
    
    private func insertMarkdown(_ prefix: String, _ suffix: String) {
        // Simple insertion at end for now
        // TODO: Insert at cursor position
        content += prefix
        if !suffix.isEmpty {
            content += suffix
        }
    }
}

// MARK: - Format Button

private struct FormatButton: View {
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .foregroundStyle(Color.themeTextSecondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Markdown Preview (Basic)

struct MarkdownView: View {
    let content: String
    
    var body: some View {
        Text(attributedContent)
            .textSelection(.enabled)
    }
    
    private var attributedContent: AttributedString {
        // Parse markdown to AttributedString (basic implementation)
        do {
            return try AttributedString(markdown: content, options: .init(
                allowsExtendedAttributes: true,
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            ))
        } catch {
            return AttributedString(content)
        }
    }
}

// MARK: - Preview

#Preview {
    NoteEditorView(
        content: .constant("""
        # My Notes
        
        This is some **bold** and *italic* text.
        
        ## Shopping List
        - Item 1
        - Item 2
        - Item 3
        
        > A quote here
        
        Some `inline code` too.
        """),
        isSaving: false
    )
    .frame(width: 600, height: 400)
}
