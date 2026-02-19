//
//  SessionViewModel.swift
//  Relay it!
//
//  Created by Relay it! on 2026/1/17.
//

import Foundation
import SwiftUI
import Combine

/// Chat message model with timestamp for timeline ordering
struct ChatMessage: Identifiable {
    let id: UUID
    let isUser: Bool
    let text: String
    let timestamp: Date
    // v2 fields
    let intent: String?
    let noteOperationType: String?
    let noteOperationContent: String?
    let referencedScreenshotIds: [String]?
    let suggestedFollowUps: [String]?
    
    init(
        id: UUID = UUID(),
        isUser: Bool,
        text: String,
        timestamp: Date = Date(),
        intent: String? = nil,
        noteOperationType: String? = nil,
        noteOperationContent: String? = nil,
        referencedScreenshotIds: [String]? = nil,
        suggestedFollowUps: [String]? = nil
    ) {
        self.id = id
        self.isUser = isUser
        self.text = text
        self.timestamp = timestamp
        self.intent = intent
        self.noteOperationType = noteOperationType
        self.noteOperationContent = noteOperationContent
        self.referencedScreenshotIds = referencedScreenshotIds
        self.suggestedFollowUps = suggestedFollowUps
    }
}

/// Timeline item for unified display
enum TimelineItem: Identifiable {
    case entity(ExtractedInfo)
    case chat(ChatMessage)
    
    var id: UUID {
        switch self {
        case .entity(let e): return e.id
        case .chat(let c): return c.id
        }
    }
    
    var timestamp: Date {
        switch self {
        case .entity(let e): return e.createdAt
        case .chat(let c): return c.timestamp
        }
    }
}

/// ViewModel for a single session's content
@MainActor
class SessionViewModel: ObservableObject {
    let sessionId: UUID
    
    @Published var screenshots: [Screenshot] = []
    @Published var entities: [ExtractedInfo] = []
    @Published var selectedEntityIds: Set<UUID> = []
    @Published var isLoading = false
    @Published var isRegenerating = false
    @Published var isConfirmingDelete = false  // Two-step delete confirmation
    @Published var searchQuery = ""
    @Published var error: String?
    
    // Chat state
    @Published var chatMessages: [ChatMessage] = []
    @Published var chatInput = ""
    @Published var isChatLoading = false
    @Published var lastSuggestedFollowUps: [String]?
    
    // Session summary (from regenerate API)
    @Published var sessionSummary: String?
    @Published var sessionCategory: String?
    
    // Note editor state
    @Published var note: SessionNote?
    @Published var noteContent: String = ""
    @Published var isNoteSaving = false
    @Published var aiHighlightStartIndex: Int = -1  // Character index where AI text starts
    @Published var aiHighlightLength: Int = 0
    @Published var aiHighlightActive = false        // Whether to show highlight
    @Published var aiSuggestionHint: String?
    @Published var cursorInsertionIndex: Int = 0
    @Published var cursorAnchor: CGPoint = .zero

    private var lastSavedContent: String = ""  // Track what was last saved
    private var aiUndoStack: [AIEditSnapshot] = []
    private var saveTask: Task<Void, Never>?
    private var highlightTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var lastCheckedContent: String = ""
    private var cancellables = Set<AnyCancellable>()

    private let supabase = SupabaseService.shared
    private let api = APIService.shared

    private struct AIEditSnapshot {
        let previousContent: String
        let previousCursorIndex: Int
    }

    init(sessionId: UUID) {
        self.sessionId = sessionId
        setupNotifications()

        // Auto-save pipeline - save when content changes
        $noteContent
            .dropFirst()
            .debounce(for: 0.8, scheduler: RunLoop.main)
            .sink { [weak self] newContent in
                guard let self = self else { return }
                // Only save if content actually changed from last saved
                guard newContent != self.lastSavedContent else { return }
                Task {
                    await self.saveNote()
                }
            }
            .store(in: &cancellables)

        $noteContent
            .dropFirst()
            .debounce(for: .seconds(6), scheduler: RunLoop.main)
            .sink { [weak self] newContent in
                self?.checkForAISuggestion(newContent)
            }
            .store(in: &cancellables)
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: .screenshotCaptured,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            if let screenshot = notification.object as? Screenshot,
               screenshot.sessionId == self.sessionId {
                Task { @MainActor in
                    await self.loadData()
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .entityUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.loadData()
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Data Loading
    
    func loadData() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            async let screenshotsTask = supabase.fetchScreenshots(sessionId: sessionId)
            async let entitiesTask = supabase.fetchExtractedInfo(sessionId: sessionId)
            async let chatTask = supabase.fetchChatMessages(sessionId: sessionId)
            async let noteTask = supabase.fetchOrCreateNote(sessionId: sessionId)
            
            screenshots = try await screenshotsTask
            entities = try await entitiesTask
            
            // Load persisted chat messages
            let dbMessages = try await chatTask
            chatMessages = dbMessages.map { $0.toChatMessage() }
            
            // Load note
            let loadedNote = try await noteTask
            note = loadedNote
            lastSavedContent = loadedNote.content  // Track what's saved
            noteContent = loadedNote.content
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    // MARK: - Timeline (entities + chat, ordered by time)
    
    var timelineItems: [TimelineItem] {
        var items: [TimelineItem] = []
        
        // Add entities
        for entity in filteredEntities {
            items.append(.entity(entity))
        }
        
        // Add chat messages
        for message in chatMessages {
            items.append(.chat(message))
        }
        
        // Sort by timestamp
        return items.sorted { $0.timestamp < $1.timestamp }
    }
    
    // MARK: - Filtering & Search
    
    var filteredEntities: [ExtractedInfo] {
        guard !searchQuery.isEmpty else { return entities }
        
        let query = searchQuery.lowercased()
        return entities.filter { entity in
            // Search in entity type
            if entity.entityType?.lowercased().contains(query) == true {
                return true
            }
            
            // Search in data values
            for (key, value) in entity.data {
                if key.lowercased().contains(query) {
                    return true
                }
                if let str = value.value as? String,
                   str.lowercased().contains(query) {
                    return true
                }
            }
            
            return false
        }
    }
    
    /// Get screenshot by ID
    func screenshot(for id: UUID) -> Screenshot? {
        screenshots.first { $0.id == id }
    }
    
    /// Get screenshots for an entity
    func screenshots(for entity: ExtractedInfo) -> [Screenshot] {
        entity.screenshotIds.compactMap { id in
            screenshots.first { $0.id == id }
        }
    }
    
    // MARK: - Selection
    
    /// Get selected entities
    var selectedEntities: [ExtractedInfo] {
        entities.filter { selectedEntityIds.contains($0.id) }
    }
    
    /// Toggle entity selection
    func toggleSelection(_ entityId: UUID) {
        if selectedEntityIds.contains(entityId) {
            selectedEntityIds.remove(entityId)
        } else {
            selectedEntityIds.insert(entityId)
        }
    }
    
    // MARK: - Chat
    
    /// Check if message is a summarize command
    private func isSummarizeCommand(_ message: String) -> Bool {
        let lowered = message.lowercased()
        let keywords = ["summarize", "summary", "總結", "摘要", "概括"]
        return keywords.contains { lowered.contains($0) }
    }
    
    /// Send a chat message with conversation history and full context (v2)
    func sendChatMessage() async {
        let userMessage = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userMessage.isEmpty else { return }
        
        
        // UI Updates
        let userChatMsg = ChatMessage(isUser: true, text: userMessage)
        chatMessages.append(userChatMsg)
        chatInput = ""
        isChatLoading = true
        lastSuggestedFollowUps = nil
        
        defer { isChatLoading = false }
        
        // Save user message
        Task {
            try? await supabase.saveChatMessage(sessionId: sessionId, role: "user", content: userMessage)
        }
        
        // Build conversation history (last 20 messages)
        let history: [APIService.ChatHistoryMessage] = chatMessages
            .dropLast()  // exclude the message we just appended
            .suffix(20)
            .map { APIService.ChatHistoryMessage(role: $0.isUser ? "user" : "assistant", content: $0.text) }
        
        // Build screenshot context
        let chatScreenshots = screenshots.compactMap { screen -> APIService.ChatScreenshot? in
            let entity = entities.first { $0.screenshotIds.contains(screen.id) }
            var summary = ""
            if let entity = entity, let sum = entity.data["summary"]?.value as? String {
                summary = sum
            } else if let entity = entity, let sum = entity.data["condensed_summary"]?.value as? String {
                summary = sum
            }
            return APIService.ChatScreenshot(
                id: screen.id.uuidString,
                rawText: screen.rawText ?? "",
                summary: summary
            )
        }
        
        // Build entity context
        let chatEntities: [APIService.ChatEntity] = entities
            .filter { $0.entityType != "ai-summary" }
            .map { entity in
                var attrs: [String: String] = [:]
                for (key, value) in entity.data {
                    if let str = value.value as? String {
                        attrs[key] = str
                    }
                }
                return APIService.ChatEntity(
                    type: entity.entityType ?? "generic",
                    title: attrs["title"],
                    attributes: attrs
                )
            }
        
        let context = APIService.ChatContext(
            screenshots: chatScreenshots,
            entities: chatEntities.isEmpty ? nil : chatEntities,
            sessionName: sessionSummary,
            sessionCategory: sessionCategory
        )
        
        do {
            let response = try await api.chat(
                sessionId: sessionId,
                userMessage: userMessage,
                conversationHistory: history.isEmpty ? nil : history,
                currentNote: noteContent,
                context: context
            )
            
            // Determine note operation from v2 or fall back to v1
            let noteOpType = response.noteOperation?.type
            let noteOpContent = response.noteOperation?.content
            
            let aiMsg = ChatMessage(
                isUser: false,
                text: response.reply,
                intent: response.intent,
                noteOperationType: noteOpType,
                noteOperationContent: noteOpContent,
                referencedScreenshotIds: response.referencedScreenshots,
                suggestedFollowUps: response.suggestedFollowUps
            )
            chatMessages.append(aiMsg)
            
            // Update suggested follow-ups
            lastSuggestedFollowUps = response.suggestedFollowUps
            
            // Save AI message
            Task {
                _ = try? await supabase.saveChatMessage(sessionId: sessionId, role: "assistant", content: response.reply)
            }
            
            // Handle note operations (v2 format)
            if let operation = response.noteOperation {
                switch operation.type {
                case "append":
                    if let content = operation.content, !content.isEmpty {
                        await MainActor.run {
                            self.appendToNote(content)
                        }
                    }
                case "replace":
                    if let content = operation.content {
                        await MainActor.run {
                            let previous = self.noteContent
                            self.recordAIEditSnapshot()
                            self.noteContent = content
                            self.cursorInsertionIndex = (content as NSString).length
                            if let range = self.changedRange(from: previous, to: content) {
                                self.triggerAIHighlight(startIndex: range.location, length: range.length)
                            }
                        }
                    }
                default:
                    break  // no_change
                }
            }
            // v1 backward compatibility fallback
            else if response.noteWasModified == true, let updatedContent = response.updatedNote {
                await MainActor.run {
                    let previous = self.noteContent
                    self.recordAIEditSnapshot()
                    self.noteContent = updatedContent
                    self.cursorInsertionIndex = (updatedContent as NSString).length
                    if let range = self.changedRange(from: previous, to: updatedContent) {
                        self.triggerAIHighlight(startIndex: range.location, length: range.length)
                    }
                }
            }
            
        } catch {
            let errorMsg = "Error: \(error.localizedDescription)"
            chatMessages.append(ChatMessage(isUser: false, text: errorMsg))
            Task { _ = try? await supabase.saveChatMessage(sessionId: sessionId, role: "assistant", content: errorMsg) }
        }
    }
    
    /// Create AI summary card from chat command
    private func createSummaryFromChat(userQuery: String) async {
        do {
            // Build context from selected entities (or all if none selected, excluding existing summaries)
            let contextEntities = selectedEntityIds.isEmpty 
                ? entities.filter { $0.entityType != "ai-summary" }
                : selectedEntities.filter { $0.entityType != "ai-summary" }
            
            guard !contextEntities.isEmpty else {
                chatMessages.append(ChatMessage(isUser: false, text: "There's nothing to summarize yet. Capture some screenshots first!"))
                return
            }
            
            // Convert to API format
            let apiEntities: [APIService.Entity] = contextEntities.map { entity in
                var attrs: [String: String] = [:]
                for (key, value) in entity.data {
                    if let str = value.value as? String {
                        attrs[key] = str
                    }
                }
                return APIService.Entity(
                    type: entity.entityType ?? "generic",
                    title: attrs["title"],
                    attributes: attrs
                )
            }
            
            // Call summarize API
            let response = try await api.summarizeSession(
                sessionId: sessionId,
                sessionName: "Chat Summary",
                entities: apiEntities
            )
            
            // Create summary entity
            var summaryData: [String: AnyCodable] = [
                "summary": AnyCodable(response.condensedSummary),
                "suggested_title": AnyCodable(response.suggestedTitle),
                "item_count": AnyCodable("\(contextEntities.count)"),
                "user_query": AnyCodable(userQuery)
            ]
            
            for (index, highlight) in response.keyHighlights.enumerated() {
                summaryData["highlight_\(index + 1)"] = AnyCodable(highlight)
            }
            
            for (index, recommendation) in response.recommendations.enumerated() {
                summaryData["recommendation_\(index + 1)"] = AnyCodable(recommendation)
            }
            
            _ = try await supabase.createExtractedInfo(
                sessionId: sessionId,
                screenshotIds: [],
                entityType: "ai-summary",
                data: summaryData
            )
            
            // Add AI response to chat
            var responseText = "📝 **\(response.suggestedTitle)**\n\n"
            responseText += response.condensedSummary + "\n\n"
            
            if !response.keyHighlights.isEmpty {
                responseText += "**Key Highlights:**\n"
                for highlight in response.keyHighlights {
                    responseText += "• \(highlight)\n"
                }
                responseText += "\n"
            }
            
            if !response.recommendations.isEmpty {
                responseText += "**Recommendations:**\n"
                for recommendation in response.recommendations {
                    responseText += "• \(recommendation)\n"
                }
            }
            
            chatMessages.append(ChatMessage(isUser: false, text: responseText))
            
            // Save AI response to database
            Task {
                try? await supabase.saveChatMessage(sessionId: sessionId, role: "assistant", content: responseText)
            }
            
            // Reload data to show new summary card
            await loadData()
            
        } catch {
            let errorMsg = "Sorry, I couldn't create a summary: \(error.localizedDescription)"
            chatMessages.append(ChatMessage(isUser: false, text: errorMsg))
            
            // Save error response to database
            Task {
                try? await supabase.saveChatMessage(sessionId: sessionId, role: "assistant", content: errorMsg)
            }
        }
    }
    
    // MARK: - Delete
    
    /// Delete selected entities
    func deleteSelectedEntities() async {
        guard !selectedEntityIds.isEmpty else { return }
        
        isRegenerating = true
        defer { isRegenerating = false }
        
        do {
            for entityId in selectedEntityIds {
                try await supabase.softDeleteExtractedInfo(id: entityId)
            }
            
            entities = entities.filter { !selectedEntityIds.contains($0.id) }
            selectedEntityIds.removeAll()
            
            await loadData()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    // MARK: - Edit OCR Text
    
    func updateScreenshotText(_ screenshotId: UUID, text: String) async {
        do {
            let updated = try await supabase.updateScreenshotText(id: screenshotId, rawText: text)
            if let index = screenshots.firstIndex(where: { $0.id == screenshotId }) {
                screenshots[index] = updated
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    // MARK: - Note Editor
    
    /// Debounced save - waits 1 second after last keystroke
    private func saveNoteDebounced() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await saveNote()
        }
    }
    
    /// Save note content to database
    func saveNote() async {
        guard let noteId = note?.id else { return }
        let contentToSave = noteContent
        guard contentToSave != lastSavedContent else { return } // No change

        isNoteSaving = true

        do {
            let updated = try await supabase.updateNote(id: noteId, content: contentToSave)
            note = updated
            lastSavedContent = contentToSave  // Track successful save
            isNoteSaving = false
        } catch {
            isNoteSaving = false
            self.error = "Failed to save note: \(error.localizedDescription)"
        }
    }
    
    /// Append text to the note (used by AI)
    func appendToNote(_ text: String) {
        guard !text.isEmpty else { return }

        recordAIEditSnapshot()

        let textLength = (text as NSString).length
        let startIndex: Int

        if noteContent.isEmpty {
            startIndex = 0
            noteContent = text
        } else {
            startIndex = (noteContent as NSString).length + 2
            noteContent += "\n\n" + text
        }

        cursorInsertionIndex = min((noteContent as NSString).length, startIndex + textLength)
        triggerAIHighlight(startIndex: startIndex, length: textLength)
    }

    /// Insert text at cursor position (used by AI callout)
    func insertAtCursor(_ text: String) {
        guard !text.isEmpty else { return }

        recordAIEditSnapshot()

        let nsText = noteContent as NSString
        let safeIndex = min(max(0, cursorInsertionIndex), nsText.length)

        let prefix = nsText.substring(to: safeIndex)
        let suffix = nsText.substring(from: safeIndex)

        let needsLeadingBreak = !prefix.isEmpty && !prefix.hasSuffix("\n")
        let needsTrailingBreak = !suffix.isEmpty && !suffix.hasPrefix("\n")

        var insertion = text
        if needsLeadingBreak {
            insertion = "\n" + insertion
        }
        if needsTrailingBreak {
            insertion += "\n"
        }

        noteContent = prefix + insertion + suffix
        let visibleStart = safeIndex + (needsLeadingBreak ? 1 : 0)
        let visibleLength = (text as NSString).length

        cursorInsertionIndex = min((noteContent as NSString).length, safeIndex + (insertion as NSString).length)
        triggerAIHighlight(startIndex: visibleStart, length: visibleLength)
    }

    func updateCursorPosition(index: Int, anchor: CGPoint?) {
        cursorInsertionIndex = max(0, index)
        if let anchor {
            cursorAnchor = anchor
        }
    }

    func dismissAISuggestionHint() {
        aiSuggestionHint = nil
    }

    @discardableResult
    func undoLastAIEdit() -> Bool {
        guard let snapshot = aiUndoStack.popLast() else { return false }
        noteContent = snapshot.previousContent
        cursorInsertionIndex = min(snapshot.previousCursorIndex, (snapshot.previousContent as NSString).length)
        aiHighlightActive = false
        aiHighlightStartIndex = -1
        aiHighlightLength = 0
        return true
    }

    
    /// Trigger highlight effect for AI-inserted text at given range
    func triggerAIHighlight(startIndex: Int, length: Int) {
        highlightTask?.cancel()

        guard startIndex >= 0, length > 0 else { return }

        aiHighlightStartIndex = startIndex
        aiHighlightLength = length
        aiHighlightActive = true

        highlightTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.aiHighlightActive = false
                self.aiHighlightStartIndex = -1
                self.aiHighlightLength = 0
            }
        }
    }
    
    func runInlineAICallout(prompt: String) async throws {
        let history: [APIService.ChatHistoryMessage] = chatMessages
            .suffix(20)
            .map { APIService.ChatHistoryMessage(role: $0.isUser ? "user" : "assistant", content: $0.text) }

        let context = buildChatContext()

        let response = try await api.chat(
            sessionId: sessionId,
            userMessage: prompt,
            conversationHistory: history.isEmpty ? nil : history,
            currentNote: noteContent,
            context: context
        )

        let userMessage = ChatMessage(isUser: true, text: prompt)
        let aiMessage = ChatMessage(
            isUser: false,
            text: response.reply,
            intent: response.intent,
            noteOperationType: response.noteOperation?.type,
            noteOperationContent: response.noteOperation?.content,
            referencedScreenshotIds: response.referencedScreenshots,
            suggestedFollowUps: response.suggestedFollowUps
        )
        chatMessages.append(userMessage)
        chatMessages.append(aiMessage)

        Task {
            _ = try? await supabase.saveChatMessage(sessionId: sessionId, role: "user", content: prompt)
            _ = try? await supabase.saveChatMessage(sessionId: sessionId, role: "assistant", content: response.reply)
        }

        if let operation = response.noteOperation {
            switch operation.type {
            case "replace":
                if let content = operation.content {
                    let previous = noteContent
                    recordAIEditSnapshot()
                    noteContent = content
                    cursorInsertionIndex = (content as NSString).length

                    if let range = changedRange(from: previous, to: content) {
                        triggerAIHighlight(startIndex: range.location, length: range.length)
                    }
                    return
                }
            case "append":
                if let content = operation.content, !content.isEmpty {
                    insertAtCursor(content)
                    return
                }
            default:
                break
            }
        }

        if response.noteWasModified == true, let updatedContent = response.updatedNote {
            let previous = noteContent
            recordAIEditSnapshot()
            noteContent = updatedContent
            cursorInsertionIndex = (updatedContent as NSString).length

            if let range = changedRange(from: previous, to: updatedContent) {
                triggerAIHighlight(startIndex: range.location, length: range.length)
            }
            return
        }

        insertAtCursor(response.reply)
    }

    private func buildChatContext() -> APIService.ChatContext {
        let chatScreenshots = screenshots.compactMap { screen -> APIService.ChatScreenshot? in
            let entity = entities.first { $0.screenshotIds.contains(screen.id) }
            var summary = ""
            if let entity, let sum = entity.data["summary"]?.value as? String {
                summary = sum
            } else if let entity, let sum = entity.data["condensed_summary"]?.value as? String {
                summary = sum
            }
            return APIService.ChatScreenshot(
                id: screen.id.uuidString,
                rawText: screen.rawText ?? "",
                summary: summary
            )
        }

        let chatEntities: [APIService.ChatEntity] = entities
            .filter { $0.entityType != "ai-summary" }
            .map { entity in
                var attrs: [String: String] = [:]
                for (key, value) in entity.data {
                    if let str = value.value as? String {
                        attrs[key] = str
                    }
                }
                return APIService.ChatEntity(
                    type: entity.entityType ?? "generic",
                    title: attrs["title"],
                    attributes: attrs
                )
            }

        return APIService.ChatContext(
            screenshots: chatScreenshots,
            entities: chatEntities.isEmpty ? nil : chatEntities,
            sessionName: sessionSummary,
            sessionCategory: sessionCategory
        )
    }

    private func checkForAISuggestion(_ newContent: String) {
        heartbeatTask?.cancel()

        heartbeatTask = Task { @MainActor in
            guard !Task.isCancelled else { return }

            let delta = extractDelta(from: lastCheckedContent, to: newContent)
            lastCheckedContent = newContent

            guard delta.count > 30 else {
                aiSuggestionHint = nil
                return
            }

            let lowered = delta.lowercased()
            if screenshots.count > 0 && newContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                aiSuggestionHint = "Press space to summarize your captures"
            } else if delta.contains("- ") || delta.contains("* ") {
                aiSuggestionHint = "Press space to summarize this list"
            } else if lowered.contains("vs") || lowered.contains("compare") {
                aiSuggestionHint = "Press space to add a comparison table"
            } else if delta.count > 180 {
                aiSuggestionHint = "Press space to clean up formatting"
            } else {
                aiSuggestionHint = "Press space for AI help on this section"
            }
        }
    }

    private func extractDelta(from previous: String, to current: String) -> String {
        if previous.isEmpty { return current }
        if current.hasPrefix(previous) {
            let idx = current.index(current.startIndex, offsetBy: previous.count)
            return String(current[idx...])
        }
        return current
    }

    private func recordAIEditSnapshot() {
        aiUndoStack.append(
            AIEditSnapshot(
                previousContent: noteContent,
                previousCursorIndex: cursorInsertionIndex
            )
        )

        // Keep bounded history to avoid unbounded memory growth.
        if aiUndoStack.count > 30 {
            aiUndoStack.removeFirst(aiUndoStack.count - 30)
        }
    }

    private func changedRange(from old: String, to new: String) -> NSRange? {
        let oldText = old as NSString
        let newText = new as NSString

        let oldLen = oldText.length
        let newLen = newText.length

        var prefix = 0
        while prefix < oldLen && prefix < newLen,
              oldText.character(at: prefix) == newText.character(at: prefix) {
            prefix += 1
        }

        var oldSuffix = oldLen
        var newSuffix = newLen
        while oldSuffix > prefix,
              newSuffix > prefix,
              oldText.character(at: oldSuffix - 1) == newText.character(at: newSuffix - 1) {
            oldSuffix -= 1
            newSuffix -= 1
        }

        let changedLength = max(0, newSuffix - prefix)
        guard changedLength > 0 else { return nil }
        return NSRange(location: prefix, length: changedLength)
    }

    /// Insert analysis from screenshot into note
    func addAnalysisToNote(summary: String, userIntent: String?, title: String?) {
        var insertText = ""
        
        if let title = title, !title.isEmpty {
            insertText += "## \(title)\n\n"
        }
        
        insertText += summary
        
        if let intent = userIntent, !intent.isEmpty {
            insertText += "\n\n> **Intent:** \(intent)"
        }
        
        appendToNote(insertText)  // This already triggers AI highlight
    }
}
