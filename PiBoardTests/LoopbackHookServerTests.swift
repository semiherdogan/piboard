import Foundation
import Testing
@testable import PiBoard

struct LoopbackHookServerTests {
    private struct Received: Equatable {
        let path: String
        let body: Data
    }

    private static let requestTimeout: TimeInterval = 2

    private func makeStream() -> (AsyncStream<Received>, AsyncStream<Received>.Continuation) {
        AsyncStream<Received>.makeStream()
    }

    private func request(_ url: URL, method: String, body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        request.httpMethod = method
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, try #require(response as? HTTPURLResponse))
    }

    @Test func postDeliversPathAndBodyAndAnswersEmptyJSON() async throws {
        let (stream, continuation) = makeStream()
        let server = LoopbackHookServer()
        let port = try await server.start { path, body in continuation.yield(Received(path: path, body: body)) }
        defer { server.stop() }
        let payload = Data(#"{"hook_event_name":"Stop","session_id":"abc"}"#.utf8)

        let (data, response) = try await request(try #require(URL(string: "http://127.0.0.1:\(port)/hooks/abc?x=1")), method: "POST", body: payload)

        #expect(response.statusCode == 200)
        #expect(data == Data("{}".utf8))
        let received = await stream.first { _ in true }
        #expect(received == Received(path: "/hooks/abc", body: payload))
    }

    @Test func getWithoutABodyDeliversAnEmptyBody() async throws {
        let (stream, continuation) = makeStream()
        let server = LoopbackHookServer()
        let port = try await server.start { path, body in continuation.yield(Received(path: path, body: body)) }
        defer { server.stop() }

        let (_, response) = try await request(try #require(URL(string: "http://127.0.0.1:\(port)/hooks/empty")), method: "GET")

        #expect(response.statusCode == 200)
        let received = await stream.first { _ in true }
        #expect(received == Received(path: "/hooks/empty", body: Data()))
    }

    @Test func connectionsFailAfterStop() async throws {
        let server = LoopbackHookServer()
        let port = try await server.start { _, _ in }
        server.stop()

        await #expect(throws: (any Error).self) {
            _ = try await request(try #require(URL(string: "http://127.0.0.1:\(port)/hooks/abc")), method: "GET")
        }
    }
}
