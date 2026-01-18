//
//  Session.swift
//  Relay it!
//
//  Created by Relay it! on 2026/1/17.
//

import Foundation

/// Represents a user's research session
struct Session: Identifiable, Codable, Hashable {
    let id: UUID
    let userId: UUID
    var name: String
    var description: String?
    let createdAt: Date
    var updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case description
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    init(id: UUID = UUID(), userId: UUID, name: String, description: String? = nil) {
        self.id = id
        self.userId = userId
        self.name = name
        self.description = description
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Insert/Update DTOs
extension Session {
    struct Insert: Encodable {
        let userId: UUID
        let name: String
        let description: String?
        
        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case name
            case description
        }
    }
    
    struct Update: Encodable {
        var name: String?
        var description: String?
        var updatedAt: Date = Date()
        
        enum CodingKeys: String, CodingKey {
            case name
            case description
            case updatedAt = "updated_at"
        }
    }
}
