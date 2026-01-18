//
//  ExtractedInfo.swift
//  Relay it!
//
//  Created by Relay it! on 2026/1/17.
//

import Foundation

/// Represents structured data extracted from screenshots
struct ExtractedInfo: Identifiable, Codable, Hashable {
    let id: UUID
    let sessionId: UUID
    var screenshotIds: [UUID]
    var entityType: String?
    var data: [String: AnyCodable]
    var isDeleted: Bool
    let createdAt: Date
    var updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case screenshotIds = "screenshot_ids"
        case entityType = "entity_type"
        case data
        case isDeleted = "is_deleted"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    init(
        id: UUID = UUID(),
        sessionId: UUID,
        screenshotIds: [UUID],
        entityType: String? = nil,
        data: [String: AnyCodable],
        isDeleted: Bool = false
    ) {
        self.id = id
        self.sessionId = sessionId
        self.screenshotIds = screenshotIds
        self.entityType = entityType
        self.data = data
        self.isDeleted = isDeleted
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Insert/Update DTOs
extension ExtractedInfo {
    struct Insert: Encodable {
        let sessionId: UUID
        let screenshotIds: [UUID]
        let entityType: String?
        let data: [String: AnyCodable]
        
        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case screenshotIds = "screenshot_ids"
            case entityType = "entity_type"
            case data
        }
    }
    
    struct Update: Encodable {
        var screenshotIds: [UUID]?
        var entityType: String?
        var data: [String: AnyCodable]?
        var isDeleted: Bool?
        var updatedAt: Date = Date()
        
        enum CodingKeys: String, CodingKey {
            case screenshotIds = "screenshot_ids"
            case entityType = "entity_type"
            case data
            case isDeleted = "is_deleted"
            case updatedAt = "updated_at"
        }
    }
}

// MARK: - AnyCodable for JSONB support
struct AnyCodable: Codable, Hashable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "Cannot encode value"
            ))
        }
    }
    
    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case (is NSNull, is NSNull): return true
        case (let l as Bool, let r as Bool): return l == r
        case (let l as Int, let r as Int): return l == r
        case (let l as Double, let r as Double): return l == r
        case (let l as String, let r as String): return l == r
        default: return false
        }
    }
    
    func hash(into hasher: inout Hasher) {
        switch value {
        case is NSNull: hasher.combine(0)
        case let bool as Bool: hasher.combine(bool)
        case let int as Int: hasher.combine(int)
        case let double as Double: hasher.combine(double)
        case let string as String: hasher.combine(string)
        default: hasher.combine(1)
        }
    }
}

// MARK: - Convenience accessors
extension ExtractedInfo {
    /// Get a string value from data
    func getString(_ key: String) -> String? {
        (data[key]?.value as? String)
    }
    
    /// Get an array value from data
    func getArray(_ key: String) -> [Any]? {
        (data[key]?.value as? [Any])
    }
    
    /// Get all keys in data
    var dataKeys: [String] {
        Array(data.keys).sorted()
    }
}
