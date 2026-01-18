//
//  SessionNote.swift
//  Relay it!
//
//  Created by Relay it! on 2026/1/18.
//

import Foundation

/// Represents a note document for a session
struct SessionNote: Identifiable, Codable {
    let id: UUID
    let sessionId: UUID
    var content: String
    let createdAt: Date
    var updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case content
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    init(
        id: UUID = UUID(),
        sessionId: UUID,
        content: String = ""
    ) {
        self.id = id
        self.sessionId = sessionId
        self.content = content
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Insert/Update DTOs
extension SessionNote {
    struct Insert: Encodable {
        let sessionId: UUID
        let content: String
        
        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case content
        }
    }
    
    struct Update: Encodable {
        var content: String?
        var updatedAt: Date = Date()
        
        enum CodingKeys: String, CodingKey {
            case content
            case updatedAt = "updated_at"
        }
    }
}
