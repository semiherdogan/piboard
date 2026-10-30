import Foundation

struct OpenCodeSession: Equatable, Sendable, Decodable {
    struct Tokens: Equatable, Sendable, Decodable {
        struct Cache: Equatable, Sendable, Decodable {
            let read: Int
            let write: Int
        }

        let input: Int
        let output: Int
        let reasoning: Int
        let cache: Cache
    }

    /// Epoch milliseconds.
    struct Time: Equatable, Sendable, Decodable {
        let created: Double
        let updated: Double
    }

    struct Location: Equatable, Sendable, Decodable {
        let directory: String
    }

    let id: String
    let title: String?
    let tokens: Tokens
    let cost: Double
    let time: Time
    let location: Location
}

/// A server event with the fields PiBoard reads; everything else stays in `payload`.
struct OpenCodeEvent: Equatable, Sendable {
    let type: String
    let sessionID: String?
    let payload: Data
}

enum OpenCodeClientError: Error, Equatable, LocalizedError {
    case unauthorized
    case notFound(String)
    case http(status: Int, body: String)
    case invalidResponse
    case invalidSessionID(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: "OpenCode rejected the service password."
        case .notFound(let id): "OpenCode has no session \(id)."
        case .http(let status, let body): "OpenCode answered HTTP \(status): \(body)"
        case .invalidResponse: "OpenCode sent a response PiBoard could not read."
        case .invalidSessionID(let id): "\"\(id)\" is not a valid OpenCode session id."
        }
    }
}

/// Typed access to the v2 API (`/api/...`) with HTTP basic auth. Sessions are created with the
/// client's id so the id can be in SQLite before the TUI exists.
struct OpenCodeClient: Sendable {
    static let apiPrefix = "/api"
    static let sessionPath = "/session"
    static let activePath = "/session/active"
    static let eventPath = "/event"
    static let messagePath = "/message"
    static let generatePath = "/generate"
    static let typesQuery = "types"
    /// Sent first on every stream regardless of the `types` filter.
    static let connectedEventType = "server.connected"
    static let directoryQuery = "directory"
    static let notFoundTag = "SessionNotFoundError"
    static let sessionIDPrefix = "ses_"
    private static let sessionIDPattern = "^ses_[0-9A-Za-z]+\\z"

    private static let dataKey = "data"
    private static let tagKey = "_tag"
    private static let typeKey = "type"
    private static let sessionIDKey = "sessionID"
    private static let idKey = "id"
    private static let titleKey = "title"
    private static let promptKey = "prompt"
    private static let locationKey = "location"
    private static let directoryKey = "directory"
    private static let roleKey = "role"
    private static let contentKey = "content"
    private static let textKey = "text"
    private static let timeKey = "time"
    private static let createdKey = "created"
    private static let assistantValue = "assistant"
    private static let textPartType = "text"
    private static let textSeparator = "\n"
    private static let authorizationHeader = "Authorization"
    private static let contentTypeHeader = "Content-Type"
    private static let jsonContentType = "application/json"
    private static let eventStreamContentType = "text/event-stream"
    private static let acceptHeader = "Accept"
    private static let basicScheme = "Basic"
    private static let unauthorizedStatus = 401
    private static let notFoundStatus = 404
    private static let successStatuses = 200..<300
    private static let lineFeed = UInt8(ascii: "\n")
    private static let get = "GET"
    private static let post = "POST"
    private static let delete = "DELETE"

    let baseURL: URL
    let password: String
    var session: URLSession = .shared

    /// `ses_` plus a lowercase UUID without dashes; the server requires the prefix.
    static func makeSessionID(uuid: UUID = UUID()) -> String {
        sessionIDPrefix + uuid.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// The server accepts `ses_` plus alphanumerics; ids go into URL paths, so nothing else may through.
    static func isValidSessionID(_ id: String) -> Bool {
        id.range(of: sessionIDPattern, options: .regularExpression) != nil
    }

    private static func requireValid(_ id: String) throws {
        guard isValidSessionID(id) else { throw OpenCodeClientError.invalidSessionID(id) }
    }

    func createSession(id: String, title: String, directory: URL) async throws -> OpenCodeSession {
        try Self.requireValid(id)
        let body: [String: Any] = [
            Self.idKey: id,
            Self.titleKey: title,
            Self.locationKey: [Self.directoryKey: directory.path],
        ]
        let (data, status) = try await send(Self.post, path: Self.sessionPath, body: body)
        try Self.check(status: status, data: data)
        return try Self.decodeSession(data)
    }

    func session(id: String) async throws -> OpenCodeSession? {
        try Self.requireValid(id)
        let (data, status) = try await send(Self.get, path: Self.sessionPath + "/" + id)
        if Self.isNotFound(data) {
            return nil
        }
        try Self.check(status: status, data: data)
        return try Self.decodeSession(data)
    }

    func deleteSession(id: String) async throws {
        try Self.requireValid(id)
        let (data, status) = try await send(Self.delete, path: Self.sessionPath + "/" + id)
        if Self.isNotFound(data) {
            return
        }
        try Self.check(status: status, data: data)
    }

    func generate(sessionID: String, prompt: String) async throws -> String {
        try Self.requireValid(sessionID)
        let (data, status) = try await send(
            Self.post,
            path: Self.sessionPath + "/" + sessionID + Self.generatePath,
            body: [Self.promptKey: prompt]
        )
        try Self.check(status: status, data: data)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = (object[Self.dataKey] as? [String: Any])?[Self.textKey] as? String
        else { throw OpenCodeClientError.invalidResponse }
        return text
    }

    func activeSessionIDs() async throws -> Set<String> {
        let (data, status) = try await send(Self.get, path: Self.activePath)
        try Self.check(status: status, data: data)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let active = object[Self.dataKey] as? [String: Any]
        else { throw OpenCodeClientError.invalidResponse }
        return Set(active.keys)
    }

    /// Observed shape: `{"data":[{"type":"assistant","time":{"created":ms},"content":[{"type":"text","text":"..."}]}, ...]}`,
    /// newest first. A `role` key is accepted too in case the server renames `type`.
    func lastAssistantText(sessionID: String) async throws -> String? {
        try Self.requireValid(sessionID)
        let (data, status) = try await send(Self.get, path: Self.sessionPath + "/" + sessionID + Self.messagePath)
        try Self.check(status: status, data: data)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = object[Self.dataKey] as? [[String: Any]]
        else { throw OpenCodeClientError.invalidResponse }
        let newestFirst = messages.sorted { Self.created($0) > Self.created($1) }
        for message in newestFirst where Self.isAssistant(message) {
            if let text = Self.text(of: message) {
                return text
            }
        }
        return nil
    }

    func events(types: [String]) -> AsyncThrowingStream<OpenCodeEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try makeRequest(
                        Self.get,
                        path: Self.eventPath,
                        query: types.map { URLQueryItem(name: Self.typesQuery, value: $0) }
                    )
                    request.setValue(Self.eventStreamContentType, forHTTPHeaderField: Self.acceptHeader)
                    request.timeoutInterval = .infinity
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw OpenCodeClientError.invalidResponse }
                    if http.statusCode == Self.unauthorizedStatus { throw OpenCodeClientError.unauthorized }
                    guard Self.successStatuses.contains(http.statusCode) else {
                        throw OpenCodeClientError.http(status: http.statusCode, body: "")
                    }
                    var parser = SSEParser()
                    var line: [UInt8] = []
                    for try await byte in bytes {
                        line.append(byte)
                        guard byte == Self.lineFeed else { continue }
                        for sse in parser.feed(line) {
                            if let event = Self.decodeEvent(Data(sse.data.utf8)) {
                                continuation.yield(event)
                            }
                        }
                        line.removeAll(keepingCapacity: true)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Reads `type` and `data.sessionID` from one event's JSON; nil when there is no `type`.
    static func decodeEvent(_ data: Data) -> OpenCodeEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object[typeKey] as? String
        else { return nil }
        let sessionID = (object[dataKey] as? [String: Any])?[sessionIDKey] as? String
        return OpenCodeEvent(type: type, sessionID: sessionID, payload: data)
    }

    private var authorizationValue: String {
        let credentials = OpenCodeServiceLocator.basicAuthUser + ":" + password
        return Self.basicScheme + " " + Data(credentials.utf8).base64EncodedString()
    }

    private func makeRequest(_ method: String, path: String, query: [URLQueryItem] = []) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw OpenCodeClientError.invalidResponse
        }
        components.path = Self.apiPrefix + path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw OpenCodeClientError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(authorizationValue, forHTTPHeaderField: Self.authorizationHeader)
        return request
    }

    private func send(_ method: String, path: String, body: [String: Any]? = nil) async throws -> (Data, Int) {
        var request = try makeRequest(method, path: path)
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue(Self.jsonContentType, forHTTPHeaderField: Self.contentTypeHeader)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenCodeClientError.invalidResponse }
        return (data, http.statusCode)
    }

    private static func check(status: Int, data: Data) throws {
        if status == unauthorizedStatus {
            throw OpenCodeClientError.unauthorized
        }
        guard successStatuses.contains(status) else {
            throw OpenCodeClientError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }
    }

    /// The server answers a missing session with the tag in the body; the status is not reliable.
    private static func isNotFound(_ data: Data) -> Bool {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?[tagKey] as? String == notFoundTag
    }

    private static func decodeSession(_ data: Data) throws -> OpenCodeSession {
        struct Envelope: Decodable { let data: OpenCodeSession }
        do {
            return try JSONDecoder().decode(Envelope.self, from: data).data
        } catch {
            throw OpenCodeClientError.invalidResponse
        }
    }

    private static func created(_ message: [String: Any]) -> Double {
        ((message[timeKey] as? [String: Any])?[createdKey] as? Double) ?? 0
    }

    private static func isAssistant(_ message: [String: Any]) -> Bool {
        message[typeKey] as? String == assistantValue || message[roleKey] as? String == assistantValue
    }

    private static func text(of message: [String: Any]) -> String? {
        let parts = (message[contentKey] as? [[String: Any]] ?? [])
            .filter { $0[typeKey] as? String == textPartType }
            .compactMap { $0[textKey] as? String }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: textSeparator)
    }
}
