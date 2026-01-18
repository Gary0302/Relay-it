//
//  SessionViewModel.swift
//  Relay it!
//
//  Created by Relay it! on 2026/1/17.
//

import Foundation
import SwiftUI

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
    @Published var noteContent: String = "" {
        didSet {
            // Debounced auto-save (skip during initial load)
            if !isLoadingNote {
                saveNoteDebounced()
            }
        }
    }
    @Published var isNoteSaving = false
    private var isLoadingNote = false
    private var saveTask: Task<Void, Never>?
    
    private let supabase = SupabaseService.shared
    private let api = APIService.shared
    
    init(sessionId: UUID) {
        self.sessionId = sessionId
        setupNotifications()
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
            
            // Load note (skip auto-save trigger)
            let loadedNote = try await noteTask
            note = loadedNote
            isLoadingNote = true
            noteContent = loadedNote.content
            isLoadingNote = false
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
    func sendChatMessage() async {
        let userMessage = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userMessage.isEmpty else { return }
        
        // Add user message to chat and save to database
        let userChatMsg = ChatMessage(isUser: true, text: userMessage)
        chatMessages.append(userChatMsg)
        chatInput = ""
        isChatLoading = true
        
        // Save user message to database
        Task {
            try? await supabase.saveChatMessage(sessionId: sessionId, role: "user", content: userMessage)
        }
        
        defer { isChatLoading = false }
        
        // Check if this is a summarize command
        if isSummarizeCommand(userMessage) {
            await createSummaryFromChat(userQuery: userMessage)
            return
        }
        
        do {
            // Build context from selected entities (or all if none selected)
            let contextEntities = selectedEntityIds.isEmpty ? entities : selectedEntities
            
            // Build screens array from context entities
            var screens: [(id: String, analysis: APIService.AnalyzeResponse)] = []
            
            for entity in contextEntities {
                var attributes: [String: String] = [:]
                for (key, value) in entity.data {
                    if let strValue = value.value as? String {
                        attributes[key] = strValue
                    }
                }
                
                let apiEntity = APIService.Entity(
                    type: entity.entityType ?? "generic",
                    title: attributes["title"] ?? attributes["suggested_title"],
                    attributes: attributes
                )
                
                let analysis = APIService.AnalyzeResponse(
                    rawText: screenshots.first { entity.screenshotIds.contains($0.id) }?.rawText ?? attributes["summary"] ?? "",
                    summary: attributes["summary"] ?? attributes["condensed_summary"] ?? "",
                    userIntent: attributes["user_intent"],
                    category: sessionCategory ?? "other",
                    entities: [apiEntity],
                    suggestedNotebookTitle: attributes["suggested_title"],
                    contextClues: nil
                )
                
                // Use screenshotId if available, otherwise use entity id as virtual screen
                let screenId = entity.screenshotIds.first?.uuidString ?? entity.id.uuidString
                screens.append((id: screenId, analysis: analysis))
            }
            
            // If no screens, give a helpful response without calling API
            guard !screens.isEmpty else {
                let noContextMsg = "I don't have any context to work with yet. Try capturing some screenshots first!"
                chatMessages.append(ChatMessage(isUser: false, text: noContextMsg))
                Task { try? await supabase.saveChatMessage(sessionId: sessionId, role: "assistant", content: noContextMsg) }
                return
            }
            
            // Build previous session context with user query
            let selectedContext = selectedEntityIds.isEmpty 
                ? "" 
                : "\n\n[User has selected \(selectedEntityIds.count) items to discuss]"
            
            let previousSession = APIService.PreviousSession(
                sessionSummary: (sessionSummary ?? "Session with captured screenshots") + selectedContext + "\n\nUser asked: " + userMessage,
                sessionCategory: sessionCategory ?? "other",
                entities: contextEntities.map { entity in
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
            )
            
            // Call regenerate API
            let response = try await api.regenerateSession(
                sessionId: sessionId,
                previousSession: previousSession,
                screens: screens
            )
            
            // Update session state
            sessionSummary = response.sessionSummary
            sessionCategory = response.sessionCategory
            
            // Add AI response to chat and note
            let aiResponse = response.sessionSummary.isEmpty 
                ? "I've analyzed your captures. How can I help you with them?"
                : response.sessionSummary
            chatMessages.append(ChatMessage(isUser: false, text: aiResponse))
            
            // Append to note with user question and AI response
            let chatNoteEntry = "---\n\n**You asked:** \(userMessage)\n\n**AI:** \(aiResponse)"
            appendToNote(chatNoteEntry)
            
            // Save AI response to database
            Task {
                try? await supabase.saveChatMessage(sessionId: sessionId, role: "assistant", content: aiResponse)
            }
            
        } catch {
            let errorMsg = "Sorry, I encountered an error: \(error.localizedDescription)"
            chatMessages.append(ChatMessage(isUser: false, text: errorMsg))
            
            // Save error response to database
            Task {
                try? await supabase.saveChatMessage(sessionId: sessionId, role: "assistant", content: errorMsg)
            }
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
        guard noteContent != note?.content else { return } // No change
        
        isNoteSaving = true
        defer { isNoteSaving = false }
        
        do {
            let updated = try await supabase.updateNote(id: noteId, content: noteContent)
            note = updated
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    /// Append text to the note (used by AI)
    func appendToNote(_ text: String) {
        if noteContent.isEmpty {
            noteContent = text
        } else {
            noteContent += "\n\n" + text
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
        
        appendToNote(insertText)
    }
}
