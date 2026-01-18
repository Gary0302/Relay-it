//
//  Screenshot.swift
//  Relay it!
//
//  Created by Relay it! on 2026/1/17.
//

import Foundation

/// Represents a captured screenshot in a session
struct Screenshot: Identifiable, Codable, Hashable {
    let id: UUID
    let sessionId: UUID
    let imageUrl: String
    let orderIndex: Int
    var rawText: String?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case imageUrl = "image_url"
        case orderIndex = "order_index"
        case rawText = "raw_text"
        case createdAt = "created_at"
    }
    
    init(id: UUID = UUID(), sessionId: UUID, imageUrl: String, orderIndex: Int, rawText: String? = nil) {
        self.id = id
        self.sessionId = sessionId
        self.imageUrl = imageUrl
        self.orderIndex = orderIndex
        self.rawText = rawText
        self.createdAt = Date()
    }
}

// MARK: - Insert DTO
extension Screenshot {
    struct Insert: Encodable {
        let sessionId: UUID
        let imageUrl: String
        let orderIndex: Int
        let rawText: String?
        
        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case imageUrl = "image_url"
            case orderIndex = "order_index"
            case rawText = "raw_text"
        }
    }
    
    struct Update: Encodable {
        var rawText: String?
        
        enum CodingKeys: String, CodingKey {
            case rawText = "raw_text"
        }
    }
}

// MARK: - Loading State
enum ScreenshotState: Hashable {
    case loading
    case analyzing
    case ready(Screenshot)
    case error(String)
    
    var isLoading: Bool {
        switch self {
        case .loading, .analyzing: return true
        default: return false
        }
    }
}
