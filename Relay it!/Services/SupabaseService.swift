//
//  SupabaseService.swift
//  Relay it!
//
//  Created by Relay it! on 2026/1/17.
//

import Foundation

/// Service for Supabase database and storage operations
@MainActor
class SupabaseService: ObservableObject {
    static let shared = SupabaseService()
    
    let client: SupabaseClient
    
    private init() {
        client = SupabaseClient(
            supabaseURL: Config.supabaseURL,
            supabaseKey: Config.supabaseAnonKey
        )
    }
    
    // MARK: - Sessions
    
    /// Fetch all sessions for current user
    func fetchSessions() async throws -> [Session] {
        try await client
            .from("sessions")
            .select()
            .order("updated_at", ascending: false)
            .execute()
    }
    
    /// Create a new session
    func createSession(name: String, description: String? = nil) async throws -> Session {
        guard let userId = await client.currentUserId else {
            throw SupabaseError.authError("Not authenticated")
        }
        
        let insert = Session.Insert(userId: userId, name: name, description: description)
        
        return try await client
            .insert(into: "sessions", values: insert)
            .select()
            .single()
            .execute()
    }
    
    /// Update a session
    func updateSession(id: UUID, name: String? = nil, description: String? = nil) async throws -> Session {
        var update = Session.Update()
        update.name = name
        update.description = description
        
        return try await client
            .update(table: "sessions", values: update)
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
    }
    
    /// Delete a session
    func deleteSession(id: UUID) async throws {
        try await client
            .delete(from: "sessions")
            .eq("id", value: id.uuidString)
            .execute()
    }
    
    // MARK: - Screenshots
    
    /// Fetch screenshots for a session
    func fetchScreenshots(sessionId: UUID) async throws -> [Screenshot] {
        try await client
            .from("screenshots")
            .select()
            .eq("session_id", value: sessionId.uuidString)
            .order("order_index")
            .execute()
    }
    
    /// Upload screenshot image and create record
    func uploadScreenshot(sessionId: UUID, imageData: Data, orderIndex: Int) async throws -> Screenshot {
        guard let userId = await client.currentUserId else {
            throw SupabaseError.authError("Not authenticated")
        }
        
        // Generate unique filename
        let filename = "\(userId.uuidString)/\(UUID().uuidString).png"
        
        // Upload to storage
        let imageUrl = try await client.uploadFile(
            bucket: "screenshots",
            path: filename,
            data: imageData,
            contentType: "image/png"
        )
        
        // Create screenshot record
        let insert = Screenshot.Insert(
            sessionId: sessionId,
            imageUrl: imageUrl,
            orderIndex: orderIndex,
            rawText: nil
        )
        
        return try await client
            .insert(into: "screenshots", values: insert)
            .select()
            .single()
            .execute()
    }
    
    /// Update screenshot with OCR text
    func updateScreenshotText(id: UUID, rawText: String) async throws -> Screenshot {
        let update = Screenshot.Update(rawText: rawText)
        
        return try await client
            .update(table: "screenshots", values: update)
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
    }
    
    /// Delete a screenshot
    func deleteScreenshot(id: UUID) async throws {
        try await client
            .delete(from: "screenshots")
            .eq("id", value: id.uuidString)
            .execute()
    }
    
    // MARK: - Extracted Info
    
    /// Fetch extracted info for a session
    func fetchExtractedInfo(sessionId: UUID) async throws -> [ExtractedInfo] {
        try await client
            .from("extracted_info")
            .select()
            .eq("session_id", value: sessionId.uuidString)
            .eq("is_deleted", value: "false")
            .order("created_at")
            .execute()
    }
    
    /// Create extracted info
    func createExtractedInfo(
        sessionId: UUID,
        screenshotIds: [UUID],
        entityType: String?,
        data: [String: AnyCodable]
    ) async throws -> ExtractedInfo {
        let insert = ExtractedInfo.Insert(
            sessionId: sessionId,
            screenshotIds: screenshotIds,
            entityType: entityType,
            data: data
        )
        
        return try await client
            .insert(into: "extracted_info", values: insert)
            .select()
            .single()
            .execute()
    }
    
    /// Update extracted info
    func updateExtractedInfo(id: UUID, update: ExtractedInfo.Update) async throws -> ExtractedInfo {
        try await client
            .update(table: "extracted_info", values: update)
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
    }
    
    /// Soft delete extracted info
    func softDeleteExtractedInfo(id: UUID) async throws {
        var update = ExtractedInfo.Update()
        update.isDeleted = true
        
        let _: ExtractedInfo = try await client
            .update(table: "extracted_info", values: update)
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
    }
    
    // MARK: - Chat Messages
    
    /// Fetch chat messages for a session
    func fetchChatMessages(sessionId: UUID) async throws -> [DBChatMessage] {
        try await client
            .from("chat_messages")
            .select()
            .eq("session_id", value: sessionId.uuidString)
            .order("created_at")
            .execute()
    }
    
    /// Save a chat message
    func saveChatMessage(sessionId: UUID, role: String, content: String) async throws -> DBChatMessage {
        let insert = ChatMessageInsert(sessionId: sessionId, role: role, content: content)
        
        return try await client
            .insert(into: "chat_messages", values: insert)
            .select()
            .single()
            .execute()
    }
    
    /// Delete all chat messages for a session
    func clearChatMessages(sessionId: UUID) async throws {
        try await client
            .delete(from: "chat_messages")
            .eq("session_id", value: sessionId.uuidString)
            .execute()
    }
    
    // MARK: - Session Notes
    
    /// Fetch note for a session (creates one if doesn't exist)
    func fetchOrCreateNote(sessionId: UUID) async throws -> SessionNote {
        // Try to fetch existing note
        let notes: [SessionNote] = try await client
            .from("session_notes")
            .select()
            .eq("session_id", value: sessionId.uuidString)
            .execute()
        
        if let existingNote = notes.first {
            return existingNote
        }
        
        // Create new note if doesn't exist
        let insert = SessionNote.Insert(sessionId: sessionId, content: "")
        return try await client
            .insert(into: "session_notes", values: insert)
            .select()
            .single()
            .execute()
    }
    
    /// Update note content
    func updateNote(id: UUID, content: String) async throws -> SessionNote {
        let update = SessionNote.Update(content: content)
        return try await client
            .update(table: "session_notes", values: update)
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
    }
}
