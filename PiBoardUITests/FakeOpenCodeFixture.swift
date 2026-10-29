import Darwin
import Foundation
import XCTest

// Written once on the URLSession queue, read after the waiter returns.
private final class ShutdownResult: @unchecked Sendable {
    var value = false
}

@MainActor
final class FakeOpenCodeFixture {
    private static let executablePermissions = 0o755
    private static let readinessTimeout: TimeInterval = 8
    private static let pollDelay: UInt64 = 50_000_000
    private static let authorizationHeader = "Authorization"
    private static let jsonContentType = "application/json"
    private static let contentTypeHeader = "Content-Type"
    private static let basicPrefix = "Basic "
    private static let basicUser = "opencode:"
    private static let appRootName = "app-root"
    private static let shutdownPath = "test/shutdown"
    private static let successStatus = 200
    private static let unauthorizedStatus = 401
    private static let serverError = "Fake OpenCode did not become ready"
    // Must match the install directory name in TestingConfiguration.
    private static let installDirectoryName = "opencode-bin"
    // Must match the Claude install directory name in TestingConfiguration.
    private static let claudeInstallDirectoryName = "claude-bin"
    // A subdirectory keeps the app's top-level copy of the OpenCode fake from picking up the Claude one.
    private static let claudeSourceDirectoryName = "claude"
    private static let bundledNodeSuffix = "/PiBoard.app/Contents/Resources/node/bin/node"

    let directory: URL
    /// Passed to the app as its UI-testing root; the app's copy of the fake lives under it.
    let appRoot: URL
    private let serverDirectory: URL
    let binary: URL
    let claudeBinary: URL
    private let claudeInstallDirectory: URL
    let piEntry: URL
    private var baseURL: URL?
    private var authorization = ""

    struct State: Decodable {
        let active: [String]
        let sessions: [String]
        let subscriptions: Int
        let resyncs: Int
        let streams: Int
        let blocked: Bool
        let pid: Int32
        let node: String
        let searchPath: String
    }

    init(deterministic: Bool) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("piboard-fakes-" + UUID().uuidString, isDirectory: true)
        appRoot = directory.appendingPathComponent(Self.appRootName, isDirectory: true)
        serverDirectory = appRoot.appendingPathComponent(Self.installDirectoryName, isDirectory: true)
        claudeInstallDirectory = appRoot.appendingPathComponent(Self.claudeInstallDirectoryName, isDirectory: true)
        let claudeDirectory = directory.appendingPathComponent(Self.claudeSourceDirectoryName, isDirectory: true)
        binary = directory.appendingPathComponent(FakeOpenCode.binaryName)
        claudeBinary = claudeDirectory.appendingPathComponent(FakeClaudeCode.binaryName)
        piEntry = directory.appendingPathComponent("fake-pi.js")
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        for (url, contents) in [
            (directory.appendingPathComponent(FakeOpenCode.scriptFileName), FakeOpenCode.script),
            (binary, FakeOpenCode.wrapper), (piEntry, FakePi.script),
            (claudeDirectory.appendingPathComponent(FakeClaudeCode.scriptFileName), FakeClaudeCode.script),
            (claudeBinary, FakeClaudeCode.wrapper),
        ] {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: Self.executablePermissions], ofItemAtPath: url.path)
        }
        if deterministic {
            try Data().write(to: directory.appendingPathComponent(FakeOpenCode.deterministicFileName))
            try Data().write(to: claudeDirectory.appendingPathComponent(FakeClaudeCode.deterministicFileName))
        }
    }

    private func connect() async throws {
        guard baseURL == nil else { return }
        let deadline = Date().addingTimeInterval(Self.readinessTimeout)
        let sidecar = serverDirectory.appendingPathComponent(FakeOpenCode.urlFileName)
        while !FileManager.default.fileExists(atPath: sidecar.path), Date() < deadline {
            try await Task.sleep(nanoseconds: Self.pollDelay)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecar.path), "Fake did not start")
        baseURL = URL(string: try String(contentsOf: sidecar, encoding: .utf8))
        let password = try String(contentsOf: serverDirectory.appendingPathComponent(FakeOpenCode.credentialFileName), encoding: .utf8)
        authorization = Self.basicPrefix + Data((Self.basicUser + password).utf8).base64EncodedString()
        let (_, response) = try await URLSession.shared.data(from: try XCTUnwrap(baseURL).appendingPathComponent("test/state"))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, Self.unauthorizedStatus, "Test controls require authentication")
        let current = try await state()
        XCTAssertTrue(current.node.hasSuffix(Self.bundledNodeSuffix), "Fake must use the built app's bundled Node")
        XCTAssertEqual(current.searchPath, serverDirectory.path, "Wrapper startup must work without utilities or Node on PATH")
    }

    func state() async throws -> State {
        try await connect()
        return try JSONDecoder().decode(State.self, from: await send("GET", path: "test/state"))
    }

    func control(_ command: String, sessionID: String) async throws {
        _ = try await send("POST", path: "test/control", body: ["command": command, "sessionID": sessionID])
    }

    func disconnect() async throws { _ = try await send("POST", path: "test/disconnect") }
    func reconnect() async throws { _ = try await send("POST", path: "test/reconnect") }

    func waitForState(_ description: String, matching predicate: (State) -> Bool) async throws -> State {
        let deadline = Date().addingTimeInterval(Self.readinessTimeout)
        repeat {
            let current = try await state()
            if predicate(current) { return current }
            try await Task.sleep(nanoseconds: Self.pollDelay)
        } while Date() < deadline
        XCTFail("Timed out waiting for fake state: \(description)")
        throw NSError(domain: Self.serverError, code: 1)
    }

    func stop() throws {
        defer { killOrphanedTUIs(); try? FileManager.default.removeItem(at: directory) }
        let sidecar = serverDirectory.appendingPathComponent(FakeOpenCode.urlFileName)
        let pidFile = serverDirectory.appendingPathComponent(FakeOpenCode.pidFileName)
        let recordedPID = (try? String(contentsOf: pidFile, encoding: .utf8)).flatMap { Int32($0) }
        if FileManager.default.fileExists(atPath: sidecar.path) {
            let url = try XCTUnwrap(URL(string: String(contentsOf: sidecar, encoding: .utf8)))
            let password = try String(contentsOf: serverDirectory.appendingPathComponent(FakeOpenCode.credentialFileName), encoding: .utf8)
            let ownedPID = try XCTUnwrap(recordedPID)
            var request = URLRequest(url: url.appendingPathComponent(Self.shutdownPath))
            request.httpMethod = "POST"
            request.timeoutInterval = Self.readinessTimeout
            request.setValue(Self.basicPrefix + Data((Self.basicUser + password).utf8).base64EncodedString(), forHTTPHeaderField: Self.authorizationHeader)
            let completed = XCTestExpectation(description: "Owned fake shutdown")
            let successStatus = Self.successStatus
            let succeeded = ShutdownResult()
            URLSession.shared.dataTask(with: request) { _, response, error in
                succeeded.value = error == nil && (response as? HTTPURLResponse)?.statusCode == successStatus
                completed.fulfill()
            }.resume()
            let finished = XCTWaiter().wait(for: [completed], timeout: Self.readinessTimeout) == .completed
            if !finished || !succeeded.value { Self.terminate(ownedPID) }
            XCTAssertTrue(finished && succeeded.value, "Fake shutdown request failed")
            let deadline = Date().addingTimeInterval(Self.readinessTimeout)
            while kill(ownedPID, 0) == 0, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            let result = kill(ownedPID, 0)
            let processError = errno
            XCTAssertEqual(result, -1, "Owned fake service must exit during teardown")
            XCTAssertEqual(processError, ESRCH)
        } else if let recordedPID {
            Self.terminate(recordedPID)
        }
    }

    private static func terminate(_ pid: Int32) {
        kill(pid, SIGTERM)
    }

    // A terminated app can leave its fake TUI children running, so they are killed by the pids they recorded.
    private func killOrphanedTUIs() {
        let files = [
            serverDirectory.appendingPathComponent(FakeOpenCode.tuiPidFileName),
            claudeInstallDirectory.appendingPathComponent(FakeClaudeCode.tuiPidFileName),
        ]
        for file in files {
            let pids = ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n").compactMap { Int32($0) }
            for pid in pids { kill(pid, SIGKILL) }
        }
    }

    private func send(_ method: String, path: String, body: [String: String]? = nil) async throws -> Data {
        var request = URLRequest(url: try XCTUnwrap(baseURL).appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = Self.readinessTimeout
        request.setValue(authorization, forHTTPHeaderField: Self.authorizationHeader)
        request.setValue(Self.jsonContentType, forHTTPHeaderField: Self.contentTypeHeader)
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, Self.successStatus, "Fake request failed: \(path)")
        return data
    }
}
