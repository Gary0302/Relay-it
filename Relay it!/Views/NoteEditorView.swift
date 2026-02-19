//
//  NoteEditorView.swift
//  Relay it!
//
//  Rich text editor with markdown preview for session notes
//

import SwiftUI
import AppKit

enum NoteEditorCommand: Equatable {
    case bold
    case italic
    case h1
    case h2
    case bullet
    case numbered
    case quote
    case divider
}

struct NoteEditorView: View {
    @Binding var content: String
    @Binding var showPreview: Bool

    var isSaving: Bool = false
    var aiHighlightActive: Bool = false
    var aiHighlightStartIndex: Int = -1
    var aiHighlightLength: Int = 0
    var showsToolbar: Bool = true

    var command: NoteEditorCommand?
    var commandNonce: Int = 0

    var onSpaceOnEmptyLine: ((CGPoint) -> Void)? = nil
    var onCursorChange: ((Int, CGPoint?) -> Void)? = nil
    var onAnyKeyPress: (() -> Void)? = nil
    var onUndoAIChange: (() -> Bool)? = nil

    @State private var localCommand: NoteEditorCommand?
    @State private var localCommandNonce: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            if showsToolbar {
                internalToolbar
                Divider()
            }

            editorPane
        }
        .background(Color.themeBackground)
    }

    private var internalToolbar: some View {
        HStack {
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Saving...")
                    .font(.caption)
                    .foregroundStyle(Color.themeTextSecondary)
            }
            .opacity(isSaving ? 1 : 0)

            Spacer()

            HStack(spacing: 8) {
                FormatButton(icon: "bold", action: { triggerLocalCommand(.bold) })
                FormatButton(icon: "italic", action: { triggerLocalCommand(.italic) })
                FormatButton(icon: "list.bullet", action: { triggerLocalCommand(.bullet) })
                FormatButton(icon: "list.number", action: { triggerLocalCommand(.numbered) })

            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.themeSurface)
    }

    private var editorPane: some View {
        HighlightableTextEditor(
            text: $content,
            highlightStartIndex: aiHighlightStartIndex,
            highlightLength: aiHighlightLength,
            isHighlightActive: aiHighlightActive,
            command: command ?? localCommand,
            commandNonce: command == nil ? localCommandNonce : commandNonce,
            onSpaceOnEmptyLine: onSpaceOnEmptyLine,
            onCursorChange: onCursorChange,
            onAnyKeyPress: onAnyKeyPress,
            onUndoAIChange: onUndoAIChange
        )
        .padding(16)
        .background(Color.themeBackground)
    }

    private func triggerLocalCommand(_ command: NoteEditorCommand) {
        localCommand = command
        localCommandNonce += 1
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
}

struct HighlightableTextEditor: NSViewRepresentable {
    @Binding var text: String
    var highlightStartIndex: Int
    var highlightLength: Int
    var isHighlightActive: Bool

    var command: NoteEditorCommand?
    var commandNonce: Int

    var onSpaceOnEmptyLine: ((CGPoint) -> Void)?
    var onCursorChange: ((Int, CGPoint?) -> Void)?
    var onAnyKeyPress: (() -> Void)?
    var onUndoAIChange: (() -> Bool)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

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

        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.font = .themeMono(size: 16)
        textView.textColor = NSColor(Color.themeText)
        textView.backgroundColor = NSColor.clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 8)

        textView.onSpaceOnEmptyLine = onSpaceOnEmptyLine
        textView.onAnyKeyPress = onAnyKeyPress
        textView.onUndoAIChange = onUndoAIChange

        scrollView.documentView = textView
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? HighlightingTextView else { return }

        textView.onSpaceOnEmptyLine = onSpaceOnEmptyLine
        textView.onAnyKeyPress = onAnyKeyPress
        textView.onUndoAIChange = onUndoAIChange

        let contentSize = scrollView.contentSize
        textView.textContainer?.containerSize = NSSize(
            width: contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = NSSize(width: 0, height: contentSize.height)

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            textView.applyMarkdownStyling()
        }

        if context.coordinator.lastCommandNonce != commandNonce {
            context.coordinator.lastCommandNonce = commandNonce
            context.coordinator.applyCommand(command, in: textView)
        }

        textView.updateHighlight(
            startIndex: highlightStartIndex,
            length: highlightLength,
            isActive: isHighlightActive
        )
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightableTextEditor
        weak var textView: HighlightingTextView?
        var lastCommandNonce: Int = -1

        init(_ parent: HighlightableTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            if let highlightingTextView = textView as? HighlightingTextView {
                highlightingTextView.applyMarkdownStyling()
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? HighlightingTextView else { return }
            let index = textView.selectedRange().location
            parent.onCursorChange?(index, textView.cursorAnchorPoint())
        }

        func applyCommand(_ command: NoteEditorCommand?, in textView: NSTextView) {
            guard let command else { return }

            switch command {
            case .bold:
                applyWrapped(prefix: "**", suffix: "**", in: textView)
            case .italic:
                applyWrapped(prefix: "*", suffix: "*", in: textView)
            case .h1:
                insertLiteral("# ", in: textView)
            case .h2:
                insertLiteral("## ", in: textView)
            case .bullet:
                insertLiteral("- ", in: textView)
            case .numbered:
                insertLiteral("1. ", in: textView)
            case .quote:
                insertLiteral("> ", in: textView)
            case .divider:
                insertLiteral("\n---\n", in: textView)
            }

            if let highlightingView = textView as? HighlightingTextView {
                parent.onCursorChange?(highlightingView.selectedRange().location, highlightingView.cursorAnchorPoint())
            }
        }

        private func insertLiteral(_ literal: String, in textView: NSTextView) {
            let range = textView.selectedRange()
            replace(range: range, with: literal, cursorOffset: literal.count, in: textView)
        }

        private func applyWrapped(prefix: String, suffix: String, in textView: NSTextView) {
            let range = textView.selectedRange()
            let nsString = textView.string as NSString
            let selected = range.length > 0 ? nsString.substring(with: range) : ""
            let replacement = prefix + selected + suffix

            let cursorOffset: Int
            if range.length > 0 {
                cursorOffset = replacement.count
            } else {
                cursorOffset = prefix.count
            }

            replace(range: range, with: replacement, cursorOffset: cursorOffset, in: textView)
        }

        private func replace(range: NSRange, with replacement: String, cursorOffset: Int, in textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            textStorage.replaceCharacters(in: range, with: replacement)

            let utf16Offset = (replacement as NSString).length
            let target = NSRange(location: range.location + min(cursorOffset, utf16Offset), length: 0)
            textView.setSelectedRange(target)
            textView.didChangeText()
        }
    }
}

class HighlightingTextView: NSTextView {
    private var currentHighlightRange: NSRange?
    private var fadeTimer: Timer?

    var onSpaceOnEmptyLine: ((CGPoint) -> Void)?
    var onAnyKeyPress: (() -> Void)?
    var onUndoAIChange: (() -> Bool)?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func keyDown(with event: NSEvent) {
        onAnyKeyPress?()

        let isCommandZ = event.modifierFlags.contains(.command)
            && event.charactersIgnoringModifiers?.lowercased() == "z"

        if isCommandZ, onUndoAIChange?() == true {
            return
        }

        super.keyDown(with: event)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let inserted: String
        if let str = insertString as? String {
            inserted = str
        } else if let attr = insertString as? NSAttributedString {
            inserted = attr.string
        } else {
            inserted = ""
        }

        if inserted == " " && shouldTriggerAICalloutOnSpace() {
            onSpaceOnEmptyLine?(cursorAnchorPoint())
            return
        }

        super.insertText(insertString, replacementRange: replacementRange)
    }

    func cursorAnchorPoint() -> CGPoint {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else {
            return CGPoint(x: 120, y: 120)
        }

        let location = selectedRange().location
        let glyphCount = layoutManager.numberOfGlyphs

        if glyphCount == 0 {
            let rect = layoutManager.extraLineFragmentRect
            return CGPoint(
                x: textContainerInset.width + rect.minX,
                y: textContainerInset.height + rect.maxY + 8
            )
        }

        let safeLocation = min(max(0, location), max(0, (string as NSString).length - 1))
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: safeLocation)
        var rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)

        if rect.isEmpty {
            rect = layoutManager.extraLineFragmentRect
        }

        return CGPoint(
            x: textContainerInset.width + rect.minX,
            y: textContainerInset.height + rect.maxY + 8
        )
    }

    private func shouldTriggerAICalloutOnSpace() -> Bool {
        let selection = selectedRange()
        guard selection.length == 0 else { return false }

        let nsText = string as NSString
        guard nsText.length > 0 || selection.location == 0 else { return false }

        let location = min(selection.location, nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
        let line = nsText.substring(with: lineRange)

        return line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func applyMarkdownStyling() {
        guard let textStorage = textStorage else { return }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        let selected = selectedRanges

        let baseFont = NSFont.themeMono(size: 16)
        let boldFont = NSFont.themeMono(size: 16, weight: .semibold)
        let heading1 = NSFont.themeMono(size: 22, weight: .semibold)
        let heading2 = NSFont.themeMono(size: 20, weight: .semibold)
        let heading3 = NSFont.themeMono(size: 18, weight: .semibold)

        textStorage.beginEditing()

        textStorage.addAttributes([
            .font: baseFont,
            .foregroundColor: NSColor(Color.themeText)
        ], range: fullRange)

        let text = textStorage.string as NSString

        applyRegex(#"(?m)^(#{1,3})\s+(.+)$"#, in: text) { match in
            let marksRange = match.range(at: 1)
            let contentRange = match.range(at: 2)

            let level = text.substring(with: marksRange).count
            let headingFont: NSFont
            switch level {
            case 1: headingFont = heading1
            case 2: headingFont = heading2
            default: headingFont = heading3
            }

            textStorage.addAttribute(.foregroundColor, value: NSColor.clear, range: marksRange)
            textStorage.addAttributes([
                .font: headingFont,
                .foregroundColor: NSColor(Color.themeText)
            ], range: contentRange)
        }

        applyRegex(#"\*\*(.+?)\*\*"#, in: text) { match in
            let contentRange = match.range(at: 1)
            textStorage.addAttribute(.font, value: boldFont, range: contentRange)
        }

        applyRegex(#"`([^`]+)`"#, in: text) { match in
            let contentRange = match.range(at: 1)
            textStorage.addAttributes([
                .foregroundColor: NSColor(Color.themeAccent),
                .backgroundColor: NSColor(Color.themeCard)
            ], range: contentRange)
        }

        applyRegex(#"(?m)^>\s+.*$"#, in: text) { match in
            textStorage.addAttribute(.foregroundColor, value: NSColor(Color.themeTextSecondary), range: match.range)
        }

        applyRegex(#"(?m)^(\s*(?:[-*]|\d+\.))\s+"#, in: text) { match in
            let markerRange = match.range(at: 1)
            textStorage.addAttribute(.foregroundColor, value: NSColor(Color.themeAccent), range: markerRange)
        }

        textStorage.endEditing()
        selectedRanges = selected
    }

    private func applyRegex(_ pattern: String, in text: NSString, using block: (NSTextCheckingResult) -> Void) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let all = NSRange(location: 0, length: text.length)
        regex.enumerateMatches(in: text as String, options: [], range: all) { match, _, _ in
            guard let match else { return }
            block(match)
        }
    }

    func updateHighlight(startIndex: Int, length: Int, isActive: Bool) {
        if !isActive || startIndex < 0 || length <= 0 {
            clearHighlight()
            return
        }

        guard let textStorage = textStorage else { return }
        let totalLength = textStorage.length

        guard startIndex < totalLength else {
            clearHighlight()
            return
        }

        let clampedLength = min(length, totalLength - startIndex)
        guard clampedLength > 0 else {
            clearHighlight()
            return
        }

        let nsRange = NSRange(location: startIndex, length: clampedLength)

        if currentHighlightRange != nsRange {
            applyHighlight(at: nsRange)
            currentHighlightRange = nsRange
        }
    }

    private func applyHighlight(at range: NSRange) {
        guard let textStorage = textStorage else { return }

        textStorage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: textStorage.length))

        let highlightColor = NSColor.systemGreen.withAlphaComponent(0.25)
        textStorage.addAttribute(.backgroundColor, value: highlightColor, range: range)

        scrollRangeToVisible(range)
        startFadeAnimation()
    }

    private func startFadeAnimation() {
        fadeTimer?.invalidate()

        fadeTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            self?.fadeOutHighlight()
        }
    }

    private func fadeOutHighlight() {
        guard let range = currentHighlightRange else { return }

        let steps = 20
        let stepDuration = 1.0 / Double(steps)
        var currentStep = 0

        Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            currentStep += 1
            let progress = CGFloat(currentStep) / CGFloat(steps)
            let newOpacity = 0.25 * (1.0 - progress)

            if let textStorage = self.textStorage,
               range.location + range.length <= textStorage.length {
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

            if !currentList.isEmpty {
                if isNumberedList {
                    blocks.append(AnyView(numberedListView(currentList)))
                } else {
                    blocks.append(AnyView(bulletListView(currentList)))
                }
                currentList = []
            }

            if trimmed.isEmpty {
                continue
            }

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
                blocks.append(AnyView(
                    Divider()
                        .background(Color.themeDivider)
                        .padding(.vertical, 8)
                ))
            } else {
                blocks.append(AnyView(
                    Text(inlineMarkdown(trimmed))
                        .font(.body)
                        .foregroundStyle(Color.themeText)
                        .textSelection(.enabled)
                ))
            }
        }

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
            result.foregroundColor = NSColor(Color.themeText)
            return result
        } catch {
            return AttributedString(text)
        }
    }
}

#Preview {
    NoteEditorView(
        content: .constant("# Notes"),
        showPreview: .constant(false),
        isSaving: false,
        aiHighlightActive: false
    )
    .frame(width: 700, height: 500)
}
