//
//  ChatMessage.swift
//  Relay it!
//
//  Persistent chat message model for database storage
//

import Foundation

/// Persistent chat message stored in Supabase
struct DBChatMessage: Codable, Identifiable {
    let id: UUID
    let sessionId: UUID
    let role: String  // "user" or "assistant"
    let content: String
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case role
        case content
        case createdAt = "created_at"
    }
    
    var isUser: Bool {
        role == "user"
    }
    
    /// Convert to in-memory ChatMessage for UI
    func toChatMessage() -> ChatMessage {
        ChatMessage(id: id, isUser: isUser, text: content, timestamp: createdAt)
    }
}

/// Request model for inserting chat message
struct ChatMessageInsert: Encodable {
    let sessionId: UUID
    let role: String
    let content: String
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case role
        case content
    }
}
