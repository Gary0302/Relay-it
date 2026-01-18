//
//  SupabaseClient.swift
//  Relay it!
//
//  Lightweight Supabase client without external dependencies
//

import Foundation

/// Lightweight Supabase client using REST API
actor SupabaseClient {
    let url: URL
    let anonKey: String
    private var accessToken: String?
    
    private let session = URLSession.shared
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    
    init(supabaseURL: URL, supabaseKey: String) {
        self.url = supabaseURL
        self.anonKey = supabaseKey
        
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            // Try ISO8601 with fractional seconds
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(dateString)")
        }
        
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }
    
    // MARK: - Auth
    
    struct AuthResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let user: User
        
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case user
        }
    }
    
    struct User: Decodable {
        let id: UUID
        let email: String?
    }
    
    struct AuthError: Decodable {
        let error: String?
        let errorDescription: String?
        let message: String?
        let errorCode: String?
        let msg: String?
        
        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
            case message
            case errorCode = "error_code"
            case msg
        }
        
        var displayMessage: String {
            // Check for specific error codes
            if errorCode == "user_already_exists" {
                return "Email already registered. Please sign in instead."
            }
            if errorCode == "invalid_credentials" {
                return "Invalid email or password"
            }
            // Fall back to other messages
            return message ?? msg ?? errorDescription ?? error ?? "Unknown error"
        }
    }
    
    /// Sign in with email and password
    func signIn(email: String, password: String) async throws -> AuthResponse {
        let endpoint = url.appendingPathComponent("auth/v1/token")
        var urlComponents = URLComponents(url: endpoint, resolvingAgainstBaseURL: true)!
        urlComponents.queryItems = [URLQueryItem(name: "grant_type", value: "password")]
        
        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        
        let body = ["email": email, "password": password]
        request.httpBody = try encoder.encode(body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            if let authError = try? decoder.decode(AuthError.self, from: data) {
                throw SupabaseError.authError(authError.displayMessage)
            }
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
        
        let authResponse = try decoder.decode(AuthResponse.self, from: data)
        self.accessToken = authResponse.accessToken
        return authResponse
    }
    
    /// Sign up with email and password
    func signUp(email: String, password: String) async throws -> AuthResponse {
        let endpoint = url.appendingPathComponent("auth/v1/signup")
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        
        let body = ["email": email, "password": password]
        request.httpBody = try encoder.encode(body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 && httpResponse.statusCode != 201 {
            if let authError = try? decoder.decode(AuthError.self, from: data) {
                throw SupabaseError.authError(authError.displayMessage)
            }
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
        
        let authResponse = try decoder.decode(AuthResponse.self, from: data)
        self.accessToken = authResponse.accessToken
        return authResponse
    }
    
    /// Set access token (for session restoration)
    func setAccessToken(_ token: String) {
        self.accessToken = token
    }
    
    /// Get current user ID
    var currentUserId: UUID? {
        guard let token = accessToken else { return nil }
        // Decode JWT to get user ID
        let parts = token.split(separator: ".")
        guard parts.count == 3,
              let payload = Data(base64Encoded: String(parts[1]).base64Padded()) else {
            return nil
        }
        
        struct JWTPayload: Decodable {
            let sub: String
        }
        
        guard let decoded = try? JSONDecoder().decode(JWTPayload.self, from: payload),
              let uuid = UUID(uuidString: decoded.sub) else {
            return nil
        }
        
        return uuid
    }
    
    // MARK: - Database
    
    /// Query a table
    func from<T: Decodable>(_ table: String) -> QueryBuilder<T> {
        QueryBuilder(client: self, table: table)
    }
    
    /// Execute a database request
    func execute<T: Decodable>(
        table: String,
        method: String,
        body: Data?,
        queryItems: [URLQueryItem]
    ) async throws -> T {
        var endpoint = url.appendingPathComponent("rest/v1/\(table)")
        
        if !queryItems.isEmpty {
            var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: true)!
            components.queryItems = queryItems
            endpoint = components.url!
        }
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        }
        
        // For inserts/updates, request to return the data
        if method == "POST" || method == "PATCH" {
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        }
        
        if let body = body {
            request.httpBody = body
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.databaseError(errorMessage)
        }
        
        return try decoder.decode(T.self, from: data)
    }
    
    /// Execute a void database request
    func executeVoid(
        table: String,
        method: String,
        body: Data?,
        queryItems: [URLQueryItem]
    ) async throws {
        var endpoint = url.appendingPathComponent("rest/v1/\(table)")
        
        if !queryItems.isEmpty {
            var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: true)!
            components.queryItems = queryItems
            endpoint = components.url!
        }
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        }
        
        if let body = body {
            request.httpBody = body
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.databaseError(errorMessage)
        }
    }
    
    // MARK: - Storage
    
    /// Upload a file to storage
    func uploadFile(bucket: String, path: String, data: Data, contentType: String) async throws -> String {
        let endpoint = url
            .appendingPathComponent("storage/v1/object")
            .appendingPathComponent(bucket)
            .appendingPathComponent(path)
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        request.httpBody = data
        
        let (responseData, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.storageError(errorMessage)
        }
        
        // Return public URL
        return url
            .appendingPathComponent("storage/v1/object/public")
            .appendingPathComponent(bucket)
            .appendingPathComponent(path)
            .absoluteString
    }
}

// MARK: - Query Builder

class QueryBuilder<T: Decodable> {
    private let client: SupabaseClient
    private let table: String
    private var queryItems: [URLQueryItem] = []
    private var selectColumns: String = "*"
    
    init(client: SupabaseClient, table: String) {
        self.client = client
        self.table = table
    }
    
    func select(_ columns: String = "*") -> Self {
        selectColumns = columns
        queryItems.append(URLQueryItem(name: "select", value: columns))
        return self
    }
    
    func eq(_ column: String, value: String) -> Self {
        queryItems.append(URLQueryItem(name: column, value: "eq.\(value)"))
        return self
    }
    
    func order(_ column: String, ascending: Bool = true) -> Self {
        let direction = ascending ? "asc" : "desc"
        queryItems.append(URLQueryItem(name: "order", value: "\(column).\(direction)"))
        return self
    }
    
    func single() -> SingleQueryBuilder<T> {
        queryItems.append(URLQueryItem(name: "limit", value: "1"))
        return SingleQueryBuilder(client: client, table: table, queryItems: queryItems)
    }
    
    func execute() async throws -> [T] {
        if !queryItems.contains(where: { $0.name == "select" }) {
            queryItems.insert(URLQueryItem(name: "select", value: "*"), at: 0)
        }
        return try await client.execute(table: table, method: "GET", body: nil, queryItems: queryItems)
    }
}

class SingleQueryBuilder<T: Decodable> {
    private let client: SupabaseClient
    private let table: String
    private var queryItems: [URLQueryItem]
    
    init(client: SupabaseClient, table: String, queryItems: [URLQueryItem]) {
        self.client = client
        self.table = table
        self.queryItems = queryItems
    }
    
    func execute() async throws -> T {
        let results: [T] = try await client.execute(table: table, method: "GET", body: nil, queryItems: queryItems)
        guard let first = results.first else {
            throw SupabaseError.notFound
        }
        return first
    }
}

// MARK: - Insert/Update Builders

extension SupabaseClient {
    func insert<T: Encodable, R: Decodable>(into table: String, values: T) -> InsertBuilder<R> {
        InsertBuilder(client: self, table: table, values: values)
    }
    
    func update<T: Encodable, R: Decodable>(table: String, values: T) -> UpdateBuilder<R> {
        UpdateBuilder(client: self, table: table, values: values)
    }
    
    func delete(from table: String) -> DeleteBuilder {
        DeleteBuilder(client: self, table: table)
    }
}

class InsertBuilder<R: Decodable> {
    private let client: SupabaseClient
    private let table: String
    private let body: Data
    private var queryItems: [URLQueryItem] = []

    init<T: Encodable>(client: SupabaseClient, table: String, values: T) {
        self.client = client
        self.table = table
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.body = (try? encoder.encode(values)) ?? Data()
    }
    
    func select(_ columns: String = "*") -> Self {
        queryItems.append(URLQueryItem(name: "select", value: columns))
        return self
    }
    
    func single() -> Self {
        return self
    }
    
    func execute() async throws -> R {
        let results: [R] = try await client.execute(table: table, method: "POST", body: body, queryItems: queryItems)
        guard let first = results.first else {
            throw SupabaseError.notFound
        }
        return first
    }
}

class UpdateBuilder<R: Decodable> {
    private let client: SupabaseClient
    private let table: String
    private let body: Data
    private var queryItems: [URLQueryItem] = []

    init<T: Encodable>(client: SupabaseClient, table: String, values: T) {
        self.client = client
        self.table = table
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.body = (try? encoder.encode(values)) ?? Data()
    }
    
    func eq(_ column: String, value: String) -> Self {
        queryItems.append(URLQueryItem(name: column, value: "eq.\(value)"))
        return self
    }
    
    func select(_ columns: String = "*") -> Self {
        queryItems.append(URLQueryItem(name: "select", value: columns))
        return self
    }
    
    func single() -> Self {
        return self
    }
    
    func execute() async throws -> R {
        let results: [R] = try await client.execute(table: table, method: "PATCH", body: body, queryItems: queryItems)
        guard let first = results.first else {
            throw SupabaseError.notFound
        }
        return first
    }
}

class DeleteBuilder {
    private let client: SupabaseClient
    private let table: String
    private var queryItems: [URLQueryItem] = []
    
    init(client: SupabaseClient, table: String) {
        self.client = client
        self.table = table
    }
    
    func eq(_ column: String, value: String) -> Self {
        queryItems.append(URLQueryItem(name: column, value: "eq.\(value)"))
        return self
    }
    
    func execute() async throws {
        try await client.executeVoid(table: table, method: "DELETE", body: nil, queryItems: queryItems)
    }
}

// MARK: - Errors

enum SupabaseError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case authError(String)
    case databaseError(String)
    case storageError(String)
    case notFound
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from server"
        case .httpError(let code): return "HTTP error: \(code)"
        case .authError(let msg): return "Auth error: \(msg)"
        case .databaseError(let msg): return "Database error: \(msg)"
        case .storageError(let msg): return "Storage error: \(msg)"
        case .notFound: return "Resource not found"
        }
    }
}

// MARK: - String Extension

extension String {
    func base64Padded() -> String {
        var result = self
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        while result.count % 4 != 0 {
            result += "="
        }
        return result
    }
}
