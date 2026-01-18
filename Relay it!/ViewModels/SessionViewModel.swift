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
    
    init(id: UUID = UUID(), isUser: Bool, text: String, timestamp: Date = Date()) {
        self.id = id
        self.isUser = isUser
        self.text = text
        self.timestamp = timestamp
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
    
    // Session summary (from regenerate API)
    @Published var sessionSummary: String?
    @Published var sessionCategory: String?
    
    // Note editor state
    @Published var note: SessionNote?
    @Published var noteContent: String = ""
    @Published var isNoteSaving = false
    @Published var aiHighlightStartIndex: Int = -1  // Character index where AI text starts
    @Published var aiHighlightActive = false        // Whether to show highlight
    private var lastSavedContent: String = ""  // Track what was last saved
    private var saveTask: Task<Void, Never>?
    private var highlightTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private let supabase = SupabaseService.shared
    private let api = APIService.shared

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
    
    /// Send a chat message with selected entities context
    /// Send a chat message with full context to the Chat API
    func sendChatMessage() async {
        let userMessage = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userMessage.isEmpty else { return }
        
        // Save note length BEFORE API call for accurate highlight positioning
        // Use UTF-16 length for NSTextStorage compatibility
        let noteContentLengthBeforeAPI = (noteContent as NSString).length
        
        // UI Updates
        let userChatMsg = ChatMessage(isUser: true, text: userMessage)
        chatMessages.append(userChatMsg)
        chatInput = ""
        isChatLoading = true
        
        defer { isChatLoading = false }
        
        // Save user message
        Task {
            try? await supabase.saveChatMessage(sessionId: sessionId, role: "user", content: userMessage)
        }
        
        // Prepare Context
        let chatScreenshots = screenshots.compactMap { screen -> APIService.ChatScreenshot? in
            let entity = entities.first { $0.screenshotIds.contains(screen.id) }
            // Get summary from entity attributes if available
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
        
        let context = APIService.ChatContext(
            screenshots: chatScreenshots,
            sessionName: sessionSummary, 
            sessionCategory: sessionCategory
        )
        
        do {
            let response = try await api.chat(
                sessionId: sessionId,
                userMessage: userMessage,
                currentNote: noteContent,
                context: context
            )
            
            // Handle Response
            let aiMsg = ChatMessage(isUser: false, text: response.reply)
            chatMessages.append(aiMsg)
            
            // Save AI message
            Task {
                try? await supabase.saveChatMessage(sessionId: sessionId, role: "assistant", content: response.reply)
            }
            
            // Update Note
            if response.noteWasModified, let updatedContent = response.updatedNote {
                // AI modified the note directly
                await MainActor.run {
                    let updatedLength = (updatedContent as NSString).length
                    self.noteContent = updatedContent
                    
                    // Only highlight if new content was actually added
                    if updatedLength > noteContentLengthBeforeAPI {
                        // Highlight starts where original content ended
                        self.triggerAIHighlight(startIndex: noteContentLengthBeforeAPI)
                    }
                }
            } else {
                // AI answered a question - append to note log
                let chatLog = "---\n\n**You:** \(userMessage)\n\n**AI:** \(response.reply)"
                await MainActor.run {
                    self.appendToNote(chatLog)
                }
            }
            
        } catch {
            let errorMsg = "Error: \(error.localizedDescription)"
            chatMessages.append(ChatMessage(isUser: false, text: errorMsg))
            Task { try? await supabase.saveChatMessage(sessionId: sessionId, role: "assistant", content: errorMsg) }
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
        // Track where new text will start using UTF-16 length for NSTextStorage compatibility
        let startIndex: Int
        if noteContent.isEmpty {
            startIndex = 0
            noteContent = text
        } else {
            // Use UTF-16 count for accurate NSTextStorage positioning
            startIndex = (noteContent as NSString).length + 2  // +2 for "\n\n"
            noteContent += "\n\n" + text
        }
        triggerAIHighlight(startIndex: startIndex)
    }
    
    /// Trigger highlight effect for AI-inserted text at given start index
    func triggerAIHighlight(startIndex: Int) {
        highlightTask?.cancel()
        
        // Only highlight if there's something to highlight
        guard startIndex >= 0 else { return }
        
        aiHighlightStartIndex = startIndex
        aiHighlightActive = true
        
        highlightTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.aiHighlightActive = false
                self.aiHighlightStartIndex = -1
            }
        }
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
