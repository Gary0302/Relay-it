//
//  AppState.swift
//  Relay it!
//
//  Created by Relay it! on 2026/1/17.
//

import Foundation
import SwiftUI

/// Global application state
@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    // Services
    let auth = AuthService.shared
    let supabase = SupabaseService.shared
    let api = APIService.shared
    let screenCapture = ScreenCaptureService.shared
    
    // State
    @Published var sessions: [Session] = []
    @Published var currentSessionId: UUID?
    @Published var isLoading = false
    @Published var isSummarizing = false
    @Published var error: AppError?
    @Published var showCaptureSuccess = false
    
    private init() {
        setupHotkey()
    }
    
    // MARK: - Current Session
    
    var currentSession: Session? {
        sessions.first { $0.id == currentSessionId }
    }
    
    // MARK: - Session Management
    
    /// Load all sessions
    func loadSessions() async {
        guard auth.isAuthenticated else { return }
        isLoading = true
        
        do {
            sessions = try await supabase.fetchSessions()
            
            // Select first session if none selected
            if currentSessionId == nil, let first = sessions.first {
                currentSessionId = first.id
            }
        } catch {
            // Check for JWT expired error
            let errorMsg = error.localizedDescription
            if errorMsg.contains("JWT expired") || errorMsg.contains("PGRST303") {
                // Auto logout on expired token
                try? await auth.signOut()
                self.error = .sessionExpired
            } else {
                self.error = .loadFailed(errorMsg)
            }
        }
        
        isLoading = false
    }
    
    /// Create new session
    func createSession(name: String) async {
        do {
            let session = try await supabase.createSession(name: name)
            sessions.insert(session, at: 0)
            currentSessionId = session.id
        } catch {
            self.error = .createFailed(error.localizedDescription)
        }
    }
    
    /// Delete session
    func deleteSession(_ sessionId: UUID) async {
        do {
            try await supabase.deleteSession(id: sessionId)
            sessions.removeAll { $0.id == sessionId }
            
            // Select another session if current was deleted
            if currentSessionId == sessionId {
                currentSessionId = sessions.first?.id
            }
        } catch {
            self.error = .deleteFailed(error.localizedDescription)
        }
    }
    
    /// Rename session
    func renameSession(_ sessionId: UUID, name: String) async {
        do {
            let updated = try await supabase.updateSession(id: sessionId, name: name)
            if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
                sessions[index] = updated
            }
        } catch {
            self.error = .updateFailed(error.localizedDescription)
        }
    }
    
    /// Summarize current session - adds AI summary to current or new session
    func summarizeSession(createNewSession: Bool = false) async {
        guard let currentId = currentSessionId else {
            error = .noSession
            return
        }
        
        isSummarizing = true
        defer { isSummarizing = false }
        
        do {
            // Fetch all entities from current session (exclude existing summaries)
            let allEntities = try await supabase.fetchExtractedInfo(sessionId: currentId)
            let entities = allEntities.filter { $0.entityType != "ai-summary" }
            
            guard !entities.isEmpty else {
                error = .loadFailed("No data to summarize")
                return
            }
            
            // Get current session name
            let currentSession = sessions.first { $0.id == currentId }
            let baseName = currentSession?.name ?? "Session"
            
            // Convert entities to API format
            let apiEntities: [APIService.Entity] = entities.map { entity in
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
            
            // Call AI summarize API
            let response = try await api.summarizeSession(
                sessionId: currentId,
                sessionName: baseName,
                entities: apiEntities
            )
            
            // Determine target session
            let targetSessionId: UUID
            if createNewSession {
                // Create new session with AI-suggested title
                let newSession = try await supabase.createSession(
                    name: response.suggestedTitle,
                    description: response.condensedSummary
                )
                sessions.insert(newSession, at: 0)
                targetSessionId = newSession.id
                currentSessionId = newSession.id
            } else {
                targetSessionId = currentId
            }
            
            // Create summary entity with AI response
            var summaryData: [String: AnyCodable] = [
                "summary": AnyCodable(response.condensedSummary),
                "suggested_title": AnyCodable(response.suggestedTitle),
                "item_count": AnyCodable("\(entities.count)")
            ]
            
            // Add key highlights
            for (index, highlight) in response.keyHighlights.enumerated() {
                summaryData["highlight_\(index + 1)"] = AnyCodable(highlight)
            }
            
            // Add recommendations
            for (index, recommendation) in response.recommendations.enumerated() {
                summaryData["recommendation_\(index + 1)"] = AnyCodable(recommendation)
            }
            
            // Create the summary entity
            _ = try await supabase.createExtractedInfo(
                sessionId: targetSessionId,
                screenshotIds: [],
                entityType: "ai-summary",
                data: summaryData
            )
            
            // Notify that entities were updated
            NotificationCenter.default.post(name: .entityUpdated, object: nil)
            
            // Show success HUD
            let message = createNewSession ? "New Summary!" : "Summarized!"
            FloatingHUD.shared.show(message: message, icon: "doc.text")
            
        } catch {
            self.error = .createFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Hotkey
    
    private func setupHotkey() {
        screenCapture.registerHotkey { [weak self] in
            Task {
                await self?.captureScreenshot()
            }
        }
    }
    
    /// Capture and process screenshot
    func captureScreenshot() async {
        guard let sessionId = currentSessionId else {
            error = .noSession
            return
        }
        
        do {
            // 1. Capture screenshot
            let imageData = try await screenCapture.captureRegion()
            
            // 2. Get current screenshot count for order index
            let screenshots = try await supabase.fetchScreenshots(sessionId: sessionId)
            let orderIndex = screenshots.count
            
            // 3. FIRST: Save screenshot to Supabase (save before AI analysis)
            var screenshot = try await supabase.uploadScreenshot(
                sessionId: sessionId,
                imageData: imageData,
                orderIndex: orderIndex
            )
            
            // Post notification immediately so UI shows the new screenshot
            NotificationCenter.default.post(name: .screenshotCaptured, object: screenshot)
            
            // Show floating HUD notification (system-level, appears on top of all windows)
            FloatingHUD.shared.show(message: "Captured!", icon: "checkmark")
            
            // 4. THEN: Analyze with AI
            let analysis = try await api.analyzeScreenshot(
                imageData: imageData,
                sessionId: sessionId
            )
            
            // 5. Update screenshot with extracted text
            screenshot = try await supabase.updateScreenshotText(
                id: screenshot.id,
                rawText: analysis.rawText
            )
            
            // 6. Save each entity as extracted info
            for entity in analysis.entities {
                var dataDict: [String: AnyCodable] = [:]
                dataDict["title"] = AnyCodable(entity.title ?? "")
                dataDict["summary"] = AnyCodable(analysis.summary)
                dataDict["category"] = AnyCodable(analysis.category)
                
                // Add new context fields (safely unwrap optionals)
                if let intent = analysis.userIntent, !intent.isEmpty {
                    dataDict["user_intent"] = AnyCodable(intent)
                }
                if let clues = analysis.contextClues {
                    dataDict["is_comparison"] = AnyCodable(clues.isComparison ?? false)
                    if let decision = clues.decisionPoint {
                        dataDict["decision_point"] = AnyCodable(decision)
                    }
                    if let topics = clues.relatedTopics, !topics.isEmpty {
                        dataDict["related_topics"] = AnyCodable(topics)
                    }
                }
                
                for (key, value) in entity.attributes {
                    dataDict[key] = AnyCodable(value.stringValue)
                }
                
                _ = try await supabase.createExtractedInfo(
                    sessionId: sessionId,
                    screenshotIds: [screenshot.id],
                    entityType: entity.type,
                    data: dataDict
                )
            }
            
            // 7. If no entities but we have a summary, save as generic info
            if analysis.entities.isEmpty && !analysis.summary.isEmpty {
                var dataDict: [String: AnyCodable] = [
                    "title": AnyCodable(analysis.suggestedNotebookTitle ?? "Screenshot"),
                    "summary": AnyCodable(analysis.summary)
                ]
                
                if let intent = analysis.userIntent, !intent.isEmpty {
                    dataDict["user_intent"] = AnyCodable(intent)
                }
                if let clues = analysis.contextClues {
                    dataDict["is_comparison"] = AnyCodable(clues.isComparison ?? false)
                    if let decision = clues.decisionPoint {
                        dataDict["decision_point"] = AnyCodable(decision)
                    }
                    if let topics = clues.relatedTopics, !topics.isEmpty {
                        dataDict["related_topics"] = AnyCodable(topics)
                    }
                }
                
                _ = try await supabase.createExtractedInfo(
                    sessionId: sessionId,
                    screenshotIds: [screenshot.id],
                    entityType: analysis.category,
                    data: dataDict
                )
            }
            
            // 8. Update session name if suggested
            if let suggestedTitle = analysis.suggestedNotebookTitle,
               let session = currentSession,
               session.name == "New Session" || session.name.isEmpty {
                await renameSession(sessionId, name: suggestedTitle)
            }
            
            // Post notification to refresh UI with analysis results
            NotificationCenter.default.post(name: .entityUpdated, object: nil)
            
        } catch ScreenCaptureError.captureAborted {
            // User cancelled, not an error
        } catch {
            self.error = .captureFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Summarize to Note
    
    /// Summarize all screenshots and insert result into the note
    func summarizeAndAddToNote(viewModel: SessionViewModel) async {
        guard let currentId = currentSessionId else {
            error = .noSession
            return
        }
        
        isSummarizing = true
        defer { isSummarizing = false }
        
        do {
            // Fetch all entities from current session (exclude existing summaries)
            let allEntities = try await supabase.fetchExtractedInfo(sessionId: currentId)
            let entities = allEntities.filter { $0.entityType != "ai-summary" }
            
            guard !entities.isEmpty else {
                error = .loadFailed("No data to summarize. Capture some screenshots first!")
                return
            }
            
            // Get current session name
            let currentSession = sessions.first { $0.id == currentId }
            let baseName = currentSession?.name ?? "Session"
            
            // Convert entities to API format
            let apiEntities: [APIService.Entity] = entities.map { entity in
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
            
            // Call AI summarize/regenerate API
            let response = try await api.summarizeSession(
                sessionId: currentId,
                sessionName: baseName,
                entities: apiEntities
            )
            
            // Build markdown content from response
            var noteContent = "# \(response.suggestedTitle)\n\n"
            noteContent += response.condensedSummary + "\n\n"
            
            if !response.keyHighlights.isEmpty {
                noteContent += "## Key Highlights\n"
                for highlight in response.keyHighlights {
                    noteContent += "- \(highlight)\n"
                }
                noteContent += "\n"
            }
            
            if !response.recommendations.isEmpty {
                noteContent += "## Recommendations\n"
                for rec in response.recommendations {
                    noteContent += "- \(rec)\n"
                }
                noteContent += "\n"
            }
            
            // Append to note
            viewModel.appendToNote(noteContent)
            
            // Show success HUD
            FloatingHUD.shared.show(message: "Added to Note!", icon: "doc.text")
            
        } catch {
            self.error = .createFailed(error.localizedDescription)
        }
    }
}

// MARK: - Errors
enum AppError: LocalizedError, Identifiable {
    case loadFailed(String)
    case createFailed(String)
    case deleteFailed(String)
    case updateFailed(String)
    case noSession
    case captureFailed(String)
    case sessionExpired
    
    var id: String { errorDescription ?? "unknown" }
    
    var errorDescription: String? {
        switch self {
        case .loadFailed(let msg): return "Failed to load: \(msg)"
        case .createFailed(let msg): return "Failed to create: \(msg)"
        case .deleteFailed(let msg): return "Failed to delete: \(msg)"
        case .updateFailed(let msg): return "Failed to update: \(msg)"
        case .noSession: return "Please create or select a session first"
        case .captureFailed(let msg): return "Capture failed: \(msg)"
        case .sessionExpired: return "Your session has expired. Please log in again."
        }
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let screenshotCaptured = Notification.Name("screenshotCaptured")
    static let entityUpdated = Notification.Name("entityUpdated")
}
