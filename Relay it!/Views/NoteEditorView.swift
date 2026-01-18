//
//  NoteEditorView.swift
//  Relay it!
//
//  Rich text editor with markdown preview for session notes
//

import SwiftUI
import AppKit

struct NoteEditorView: View {
    @Binding var content: String
    @State private var showPreview = false
    var isSaving: Bool = false
    var aiHighlightActive: Bool = false
    var aiHighlightStartIndex: Int = -1  // Character index where AI text starts
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with format buttons
            HStack {
                // Saving indicator - fixed width to prevent layout shift
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Saving...")
                        .font(.caption)
                        .foregroundStyle(Color.themeTextSecondary)
                }
                .opacity(isSaving ? 1 : 0)

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
        HighlightableTextEditor(
            text: $content,
            highlightStartIndex: aiHighlightStartIndex,
            isHighlightActive: aiHighlightActive
        )
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
        .background(Color.themeCard)
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

// MARK: - Highlightable Text Editor (NSTextView wrapper)

struct HighlightableTextEditor: NSViewRepresentable {
    @Binding var text: String
    var highlightStartIndex: Int  // Character index where highlight starts
    var isHighlightActive: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        // Create scroll view
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        
        // Create text view with proper configuration for scrolling
        let contentSize = scrollView.contentSize
        
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        
        let textContainer = NSTextContainer(containerSize: NSSize(
            width: contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        ))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        
        let textView = HighlightingTextView(
            frame: NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height),
            textContainer: textContainer
        )
        
        // Configure for proper scrolling
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        
        // Text view settings
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textColor = NSColor(Color.themeText)
        textView.backgroundColor = NSColor.clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 8)
        
        scrollView.documentView = textView
        context.coordinator.textView = textView
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? HighlightingTextView else { return }
        
        // Update text container width when scroll view resizes
        let contentSize = scrollView.contentSize
        textView.textContainer?.containerSize = NSSize(
            width: contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        
        // Update text if changed externally
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }
        
        // Update highlight using start index
        textView.updateHighlight(
            startIndex: highlightStartIndex,
            isActive: isHighlightActive
        )
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightableTextEditor
        weak var textView: HighlightingTextView?
        
        init(_ parent: HighlightableTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

// MARK: - Custom NSTextView with highlight support

class HighlightingTextView: NSTextView {
    private var currentHighlightRange: NSRange?
    private var fadeTimer: Timer?
    
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    
    func updateHighlight(startIndex: Int, isActive: Bool) {
        // Clear existing highlights if not active or invalid index
        if !isActive || startIndex < 0 {
            clearHighlight()
            return
        }
        
        guard let textStorage = textStorage else { return }
        let totalLength = textStorage.length
        
        // Validate start index
        guard startIndex < totalLength else {
            clearHighlight()
            return
        }
        
        // Highlight from startIndex to end of text
        let highlightLength = totalLength - startIndex
        let nsRange = NSRange(location: startIndex, length: highlightLength)
        
        // Only re-apply if range changed
        if currentHighlightRange != nsRange {
            applyHighlight(at: nsRange)
            currentHighlightRange = nsRange
        }
    }
    
    private func applyHighlight(at range: NSRange) {
        guard let textStorage = textStorage else { return }
        
        // Remove old highlight
        textStorage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: textStorage.length))
        
        // Apply new highlight with green background
        let highlightColor = NSColor.systemGreen.withAlphaComponent(0.25)
        textStorage.addAttribute(.backgroundColor, value: highlightColor, range: range)
        
        // Scroll to show the highlighted text
        scrollRangeToVisible(range)
        
        // Start fade animation
        startFadeAnimation()
    }
    
    private func startFadeAnimation() {
        fadeTimer?.invalidate()
        
        // Wait 4 seconds, then fade out over 1 second
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            self?.fadeOutHighlight()
        }
    }
    
    private func fadeOutHighlight() {
        guard let range = currentHighlightRange else { return }
        
        // Animate the fade out
        let steps = 20
        let stepDuration = 1.0 / Double(steps)
        var currentStep = 0
        
        Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            currentStep += 1
            let progress = CGFloat(currentStep) / CGFloat(steps)
            let newOpacity = 0.25 * (1.0 - progress)
            
            if let textStorage = self.textStorage, range.location + range.length <= textStorage.length {
                let color = NSColor.systemGreen.withAlphaComponent(newOpacity)
                textStorage.addAttribute(.backgroundColor, value: color, range: range)
            }
            
            if currentStep >= steps {
                timer.invalidate()
                self.clearHighlight()
            }
        }
    }
    
    private func clearHighlight() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        
        if let textStorage = textStorage {
            textStorage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: textStorage.length))
        }
        currentHighlightRange = nil
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

// MARK: - Markdown Preview

struct MarkdownView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                block
            }
        }
        .foregroundStyle(Color.themeText)
    }

    private func parseBlocks() -> [AnyView] {
        let lines = content.components(separatedBy: "\n")
        var blocks: [AnyView] = []
        var currentList: [String] = []
        var isNumberedList = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Check for list items
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                if !currentList.isEmpty && isNumberedList {
                    blocks.append(AnyView(numberedListView(currentList)))
                    currentList = []
                }
                isNumberedList = false
                currentList.append(String(trimmed.dropFirst(2)))
                continue
            } else if let match = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                if !currentList.isEmpty && !isNumberedList {
                    blocks.append(AnyView(bulletListView(currentList)))
                    currentList = []
                }
                isNumberedList = true
                currentList.append(String(trimmed[match.upperBound...]))
                continue
            }

            // Flush current list if we hit a non-list line
            if !currentList.isEmpty {
                if isNumberedList {
                    blocks.append(AnyView(numberedListView(currentList)))
                } else {
                    blocks.append(AnyView(bulletListView(currentList)))
                }
                currentList = []
            }

            // Empty line
            if trimmed.isEmpty {
                continue
            }

            // Headings
            if trimmed.hasPrefix("### ") {
                blocks.append(AnyView(
                    Text(inlineMarkdown(String(trimmed.dropFirst(4))))
                        .font(.headline)
                        .foregroundStyle(Color.themeText)
                        .padding(.top, 8)
                ))
            } else if trimmed.hasPrefix("## ") {
                blocks.append(AnyView(
                    Text(inlineMarkdown(String(trimmed.dropFirst(3))))
                        .font(.title2.bold())
                        .foregroundStyle(Color.themeText)
                        .padding(.top, 12)
                ))
            } else if trimmed.hasPrefix("# ") {
                blocks.append(AnyView(
                    Text(inlineMarkdown(String(trimmed.dropFirst(2))))
                        .font(.title.bold())
                        .foregroundStyle(Color.themeText)
                        .padding(.top, 16)
                ))
            } else if trimmed.hasPrefix("> ") {
                // Blockquote
                blocks.append(AnyView(
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.themeAccent)
                            .frame(width: 3)
                        Text(inlineMarkdown(String(trimmed.dropFirst(2))))
                            .font(.body.italic())
                            .foregroundStyle(Color.themeTextSecondary)
                            .padding(.leading, 12)
                    }
                    .padding(.vertical, 4)
                ))
            } else if trimmed.hasPrefix("---") || trimmed.hasPrefix("***") {
                // Horizontal rule
                blocks.append(AnyView(
                    Divider()
                        .background(Color.themeDivider)
                        .padding(.vertical, 8)
                ))
            } else {
                // Regular paragraph
                blocks.append(AnyView(
                    Text(inlineMarkdown(trimmed))
                        .font(.body)
                        .foregroundStyle(Color.themeText)
                        .textSelection(.enabled)
                ))
            }
        }

        // Flush remaining list
        if !currentList.isEmpty {
            if isNumberedList {
                blocks.append(AnyView(numberedListView(currentList)))
            } else {
                blocks.append(AnyView(bulletListView(currentList)))
            }
        }

        return blocks
    }

    private func bulletListView(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(Color.themeAccent)
                        .font(.body.bold())
                    Text(inlineMarkdown(item))
                        .font(.body)
                        .foregroundStyle(Color.themeText)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func numberedListView(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .foregroundStyle(Color.themeAccent)
                        .font(.body.bold())
                        .frame(width: 20, alignment: .trailing)
                    Text(inlineMarkdown(item))
                        .font(.body)
                        .foregroundStyle(Color.themeText)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        do {
            var result = try AttributedString(markdown: text, options: .init(
                allowsExtendedAttributes: true,
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            ))
            // Ensure the text color is applied
            result.foregroundColor = NSColor(Color.themeText)
            return result
        } catch {
            return AttributedString(text)
        }
    }
}

// MARK: - Preview

#Preview("Normal") {
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
        isSaving: false,
        aiHighlightActive: false
    )
    .frame(width: 600, height: 400)
}

#Preview("AI Highlight Active") {
    // The text before "This is new AI-generated..." is about 95 characters
    NoteEditorView(
        content: .constant("""
        # My Notes
        
        This is some **bold** and *italic* text.
        
        ## Shopping List
        - Item 1
        - Item 2
        - Item 3

        This is new AI-generated content that was just added to your notes.
        """),
        isSaving: false,
        aiHighlightActive: true,
        aiHighlightStartIndex: 95  // Index where AI content starts
    )
    .frame(width: 600, height: 400)
}
