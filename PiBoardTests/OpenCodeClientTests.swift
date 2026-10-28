import Foundation
import Synchronization
import Testing
@testable import PiBoard

struct OpenCodeClientTests {
    private let password = "pw"
    private let sessionJSON = """
    {"id":"ses_abc","title":"Task","tokens":{"input":1,"output":2,"reasoning":3,"cache":{"read":4,"write":5}},\
    "cost":0.5,"time":{"created":1000,"updated":2000},"location":{"directory":"/tmp/project"}}
    """

    /// Each test gets its own host so parallel tests never share stub state.
    private func makeClient() -> (client: OpenCodeClient, host: String) {
        let host = "stub-\(UUID().uuidString.lowercased()).test"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let client = OpenCodeClient(
            baseURL: URL(string: "http://\(host)")!,
            password: password,
            session: URLSession(configuration: configuration)
        )
        return (client, host)
    }

    @Test func createSessionSendsIDTitleAndLocationWithBasicAuth() async throws {
        let (client, host) = makeClient()
        StubURLProtocol.register(host: host) { _ in .json(200, #"{"data":\#(sessionJSON)}"#) }

        let session = try await client.createSession(
            id: "ses_abc",
            title: "Task",
            directory: URL(fileURLWithPath: "/tmp/project")
        )

        let request = try #require(StubURLProtocol.requests(host: host).first)
        #expect(request.method == "POST")
        #expect(request.path == "/api/session")
        let expectedAuth = "Basic " + Data("opencode:\(password)".utf8).base64EncodedString()
        #expect(request.authorization == expectedAuth)
        let body = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        #expect(body["id"] as? String == "ses_abc")
        #expect(body["title"] as? String == "Task")
        #expect((body["location"] as? [String: Any])?["directory"] as? String == "/tmp/project")
        #expect(session.id == "ses_abc")
        #expect(session.tokens.cache == OpenCodeSession.Tokens.Cache(read: 4, write: 5))
        #expect(session.location.directory == "/tmp/project")
    }

    @Test func sessionDecodesTheEnvelope() async throws {
        let (client, host) = makeClient()
        StubURLProtocol.register(host: host) { _ in .json(200, #"{"data":\#(sessionJSON)}"#) }
        let session = try await client.session(id: "ses_abc")
        #expect(session?.title == "Task")
        #expect(session?.time == OpenCodeSession.Time(created: 1000, updated: 2000))
    }

    @Test func sessionReturnsNilForNotFoundTag() async throws {
        let (client, host) = makeClient()
        let body = #"{"_tag":"SessionNotFoundError","sessionID":"ses_x","message":"gone"}"#
        for status in [200, 404] {
            StubURLProtocol.register(host: host) { _ in .json(status, body) }
            #expect(try await client.session(id: "ses_x") == nil)
        }
    }

    @Test func deleteIsIdempotentOnNotFound() async throws {
        let (client, host) = makeClient()
        StubURLProtocol.register(host: host) { _ in
            .json(404, #"{"_tag":"SessionNotFoundError","sessionID":"ses_x","message":"gone"}"#)
        }
        try await client.deleteSession(id: "ses_x")
        let request = try #require(StubURLProtocol.requests(host: host).first)
        #expect(request.method == "DELETE")
        #expect(request.path == "/api/session/ses_x")
    }

    @Test func deleteAcceptsNoContent() async throws {
        let (client, host) = makeClient()
        StubURLProtocol.register(host: host) { _ in .json(204, "") }
        try await client.deleteSession(id: "ses_x")
    }

    @Test func activeSessionIDsParsesTheMap() async throws {
        let (client, host) = makeClient()
        StubURLProtocol.register(host: host) { _ in
            .json(200, #"{"data":{"ses_a":{"type":"running"},"ses_b":{"type":"running"}}}"#)
        }
        #expect(try await client.activeSessionIDs() == ["ses_a", "ses_b"])
        #expect(StubURLProtocol.requests(host: host).first?.path == "/api/session/active")
    }

    @Test func unauthorizedThrows() async throws {
        let (client, host) = makeClient()
        StubURLProtocol.register(host: host) { _ in .json(401, #"{"_tag":"UnauthorizedError"}"#) }
        await #expect(throws: OpenCodeClientError.unauthorized) {
            try await client.activeSessionIDs()
        }
    }

    @Test func otherStatusesThrowHTTPWithTheBody() async throws {
        let (client, host) = makeClient()
        StubURLProtocol.register(host: host) { _ in .json(500, "boom") }
        await #expect(throws: OpenCodeClientError.http(status: 500, body: "boom")) {
            try await client.activeSessionIDs()
        }
    }

    @Test func lastAssistantTextPicksTheNewestAssistantMessage() async throws {
        let (client, host) = makeClient()
        let body = """
        {"data":[
          {"id":"m3","time":{"created":30},"type":"idle","outcome":"succeeded"},
          {"id":"m2","time":{"created":20},"type":"assistant","content":[{"type":"text","text":"newest"},{"type":"reasoning","text":"skip"}]},
          {"id":"m1","time":{"created":10},"type":"assistant","content":[{"type":"text","text":"older"}]}
        ]}
        """
        StubURLProtocol.register(host: host) { _ in .json(200, body) }
        #expect(try await client.lastAssistantText(sessionID: "ses_a") == "newest")
        #expect(StubURLProtocol.requests(host: host).first?.path == "/api/session/ses_a/message")
    }

    @Test func lastAssistantTextIsNilWithoutAssistantText() async throws {
        let (client, host) = makeClient()
        StubURLProtocol.register(host: host) { _ in .json(200, #"{"data":[{"id":"m","type":"user","text":"hi"}]}"#) }
        #expect(try await client.lastAssistantText(sessionID: "ses_a") == nil)
    }

    @Test func rejectsIDsWithPathCharacters() async {
        let (client, host) = makeClient()
        StubURLProtocol.register(host: host) { _ in .json(200, "{}") }
        for id in ["ses_a/b", "../x", ""] {
            #expect(!OpenCodeClient.isValidSessionID(id))
            await #expect(throws: OpenCodeClientError.invalidSessionID(id)) { _ = try await client.session(id: id) }
            await #expect(throws: OpenCodeClientError.invalidSessionID(id)) { try await client.deleteSession(id: id) }
            await #expect(throws: OpenCodeClientError.invalidSessionID(id)) { _ = try await client.lastAssistantText(sessionID: id) }
            await #expect(throws: OpenCodeClientError.invalidSessionID(id)) {
                _ = try await client.createSession(id: id, title: "t", directory: URL(fileURLWithPath: "/tmp"))
            }
        }
        #expect(StubURLProtocol.requests(host: host).isEmpty)
        #expect(OpenCodeClient.isValidSessionID(OpenCodeClient.makeSessionID()))
    }

    @Test func makeSessionIDHasPrefixAndNoDashes() {
        let id = OpenCodeClient.makeSessionID(uuid: UUID(uuidString: "ABCDEF01-2345-6789-ABCD-EF0123456789")!)
        #expect(id == "ses_abcdef0123456789abcdef0123456789")
        #expect(OpenCodeClient.makeSessionID().hasPrefix(OpenCodeClient.sessionIDPrefix))
    }

    @Test func decodeEventReadsTypeAndSessionID() throws {
        let data = Data(#"{"type":"session.execution.started","data":{"sessionID":"ses_a"}}"#.utf8)
        let event = try #require(OpenCodeClient.decodeEvent(data))
        #expect(event.type == "session.execution.started")
        #expect(event.sessionID == "ses_a")
        #expect(event.payload == data)
    }

    @Test func decodeEventAllowsMissingSessionIDAndRejectsMissingType() {
        #expect(OpenCodeClient.decodeEvent(Data(#"{"type":"server.connected"}"#.utf8))?.sessionID == nil)
        #expect(OpenCodeClient.decodeEvent(Data(#"{"data":{}}"#.utf8)) == nil)
        #expect(OpenCodeClient.decodeEvent(Data("nope".utf8)) == nil)
    }
}

struct RecordedRequest: Sendable {
    let method: String
    let path: String
    let authorization: String?
    let body: Data
}

struct StubResponse: Sendable {
    let status: Int
    let body: Data

    static func json(_ status: Int, _ body: String) -> StubResponse {
        StubResponse(status: status, body: Data(body.utf8))
    }
}

/// Answers every request to a registered host with the host's handler and records what it saw.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private struct State {
        var handlers: [String: @Sendable (RecordedRequest) -> StubResponse] = [:]
        var requests: [String: [RecordedRequest]] = [:]
    }

    private static let state = Mutex(State())

    static func register(host: String, handler: @escaping @Sendable (RecordedRequest) -> StubResponse) {
        state.withLock { $0.handlers[host] = handler }
    }

    static func requests(host: String) -> [RecordedRequest] {
        state.withLock { $0.requests[host] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let recorded = RecordedRequest(
            method: request.httpMethod ?? "",
            path: request.url?.path ?? "",
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            body: Self.readBody(request)
        )
        let handler = Self.state.withLock { state -> (@Sendable (RecordedRequest) -> StubResponse)? in
            state.requests[host, default: []].append(recorded)
            return state.handlers[host]
        }
        let response = handler?(recorded) ?? .json(500, "no stub")
        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: response.status,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    // URLSession hands the body to a protocol as a stream, never as `httpBody`.
    private static func readBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
