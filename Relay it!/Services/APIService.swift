//
//  APIService.swift
//  Relay it!
//
//  Created by Relay it! on 2026/1/17.
//

import Foundation

/// Service for calling Vercel API endpoints
@MainActor
class APIService: ObservableObject {
    static let shared = APIService()
    
    private let session = URLSession.shared
    private let baseURL = Config.apiBaseURL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private init() {}
    
    // MARK: - Analyze Screenshot
    
    struct AnalyzeRequest: Encodable {
        let image: String  // data URL format: data:image/png;base64,...
    }
    
    struct AnalyzeResponse: Decodable, Encodable {
        let rawText: String
        let summary: String
        let userIntent: String?  // Optional - may not be present
        let category: String
        let entities: [Entity]
        let suggestedNotebookTitle: String?
        let contextClues: ContextClues?  // Optional - may not be present
    }
    
    struct ContextClues: Codable {
        let isComparison: Bool?
        let decisionPoint: String?
        let relatedTopics: [String]?
    }
    
    struct Entity: Codable {
        let type: String
        let title: String?
        let attributes: [String: AttributeValue]
        
        // Convenience initializer for creating Entity with string attributes
        init(type: String, title: String?, attributes: [String: String]) {
            self.type = type
            self.title = title
            self.attributes = attributes.mapValues { AttributeValue.string($0) }
        }
        
        // Full initializer with AttributeValue
        init(type: String, title: String?, attributeValues: [String: AttributeValue]) {
            self.type = type
            self.title = title
            self.attributes = attributeValues
        }
    }
    
    // Flexible value type for entity attributes (AI may return strings, numbers, etc.)
    enum AttributeValue: Codable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)
        case null
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let str = try? container.decode(String.self) {
                self = .string(str)
            } else if let int = try? container.decode(Int.self) {
                self = .int(int)
            } else if let double = try? container.decode(Double.self) {
                self = .double(double)
            } else if let bool = try? container.decode(Bool.self) {
                self = .bool(bool)
            } else {
                self = .null
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let s): try container.encode(s)
            case .int(let i): try container.encode(i)
            case .double(let d): try container.encode(d)
            case .bool(let b): try container.encode(b)
            case .null: try container.encodeNil()
            }
        }
        
        var stringValue: String {
            switch self {
            case .string(let s): return s
            case .int(let i): return String(i)
            case .double(let d): return String(d)
            case .bool(let b): return b ? "true" : "false"
            case .null: return ""
            }
        }
    }
    
    /// Analyze a screenshot with Gemini
    func analyzeScreenshot(
        imageData: Data,
        sessionId: UUID
    ) async throws -> AnalyzeResponse {
        // Convert to data URL format as required by the API
        let base64Image = imageData.base64EncodedString()
        let dataURL = "data:image/png;base64,\(base64Image)"
        
        let request = AnalyzeRequest(image: dataURL)
        
        return try await post("/api/analyze", body: request)
    }
    
    // MARK: - Regenerate Session
    
    struct PreviousSession: Encodable {
        let sessionSummary: String
        let sessionCategory: String
        let entities: [Entity]
    }
    
    struct ScreenInput: Encodable {
        let id: String
        let analysis: AnalyzeResponse
    }
    
    struct RegenerateRequest: Encodable {
        let sessionId: String
        let previousSession: PreviousSession?
        let screens: [ScreenInput]
    }
    
    struct RegenerateResponse: Decodable {
        let sessionId: String
        let sessionSummary: String
        let sessionCategory: String
        let entities: [Entity]
        let suggestedNotebookTitle: String?
    }
    
    /// Regenerate session summary from all screenshot analyses
    func regenerateSession(
        sessionId: UUID,
        previousSession: PreviousSession?,
        screens: [(id: String, analysis: AnalyzeResponse)]
    ) async throws -> RegenerateResponse {
        let screenInputs = screens.map { ScreenInput(id: $0.id, analysis: $0.analysis) }
        
        let request = RegenerateRequest(
            sessionId: sessionId.uuidString,
            previousSession: previousSession,
            screens: screenInputs
        )
        
        return try await post("/api/regenerate", body: request)
    }
    
    // MARK: - Summarize Session
    
    struct SummarizeRequest: Encodable {
        let sessionId: String
        let sessionName: String
        let entities: [Entity]
    }
    
    struct SummarizeResponse: Decodable {
        let condensedSummary: String
        let keyHighlights: [String]
        let recommendations: [String]
        let mergedEntities: [Entity]
        let suggestedTitle: String
    }
    
    /// Summarize session entities with AI-powered insights
    func summarizeSession(
        sessionId: UUID,
        sessionName: String,
        entities: [Entity]
    ) async throws -> SummarizeResponse {
        let request = SummarizeRequest(
            sessionId: sessionId.uuidString,
            sessionName: sessionName,
            entities: entities
        )
        
        return try await post("/api/summarize", body: request)
    }
    
    // MARK: - Chat
    
    struct ChatContext: Encodable {
        let screenshots: [ChatScreenshot]?
        let sessionName: String?
        let sessionCategory: String?
    }
    
    struct ChatScreenshot: Encodable {
        let id: String
        let rawText: String
        let summary: String
    }
    
    struct ChatRequest: Encodable {
        let sessionId: String
        let userMessage: String
        let currentNote: String
        let context: ChatContext?
    }
    
    struct ChatResponse: Decodable {
        let reply: String
        let updatedNote: String?
        let noteWasModified: Bool
    }
    
    /// Send chat message to AI with note modification capabilities
    func chat(sessionId: UUID, userMessage: String, currentNote: String, context: ChatContext?) async throws -> ChatResponse {
        let request = ChatRequest(
            sessionId: sessionId.uuidString,
            userMessage: userMessage,
            currentNote: currentNote,
            context: context
        )
        return try await post("/api/chat", body: request)
    }
    
    // MARK: - Health Check
    
    struct HealthResponse: Decodable {
        let status: String
        let geminiConfigured: Bool
        
        enum CodingKeys: String, CodingKey {
            case status
            case geminiConfigured = "gemini_configured"
        }
    }
    
    /// Check API health
    func healthCheck() async throws -> HealthResponse {
        try await get("/api/health")
    }
    
    // MARK: - HTTP Helpers
    
    private func get<T: Decodable>(_ path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        
        return try decoder.decode(T.self, from: data)
    }
    
    private func post<T: Encodable, R: Decodable>(_ path: String, body: T) async throws -> R {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        request.timeoutInterval = 60  // Longer timeout for AI analysis
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        
        do {
            return try decoder.decode(R.self, from: data)
        } catch {
            // Log the raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("API Response: \(responseString)")
            }
            throw APIError.decodingError(error.localizedDescription)
        }
    }
    
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }
    }
}

// MARK: - Errors
enum APIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .decodingError(let msg):
            return "Failed to parse response: \(msg)"
        }
    }
}
