import Foundation
@testable import PiBoard

/// A `PiRPCDriver` wired to the shared fake Pi (`TestSupport/FakePiRPC.swift`) under the bundled Node.
@MainActor
final class FakePiHarness {
    private static let sessionID = "11111111-2222-3333-4444-555555555555"
    private static let pathValue = "/usr/bin:/bin"

    let driver: PiRPCDriver
    private let directory: URL

    init(
        arguments: [String] = [],
        commandTimeout: Duration = PiRPCDriver.defaultCommandTimeout,
        gracePeriod: Duration = .seconds(ProcessQuitPolicy.gracePeriod)
    ) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = try FakePiRPC.writeScript(in: directory)
        let command = AgentLaunchCommand(
            executable: try Self.nodeExecutable(),
            arguments: [script.path, "--session-id", Self.sessionID] + arguments,
            currentDirectory: directory
        )
        driver = PiRPCDriver(
            command: command,
            launchEnvironment: ["PATH": Self.pathValue],
            commandTimeout: commandTimeout,
            gracePeriod: gracePeriod
        )
    }

    var sessionID: String { Self.sessionID }

    /// Kills the process and removes the script; call from `defer`.
    func close() {
        driver.forceKill()
        try? FileManager.default.removeItem(at: directory)
    }

    /// The hosted unit test bundle carries the app's Node; the repo copy covers a host without it.
    private static func nodeExecutable(file: String = #filePath) throws -> URL {
        if let bundled = try? BundledNode.locate() { return bundled.nodeExecutable }
        let repoRuntime = URL(fileURLWithPath: file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Runtime")
        return try BundledNode.locate(root: repoRuntime).nodeExecutable
    }
}

/// Collects what a driver reports, in order.
@MainActor
final class DriverRecorder {
    private(set) var events: [ConversationEvent] = []
    private(set) var didExit = false
    private(set) var exitCode: Int32?

    init(_ driver: any ConversationDriver) {
        driver.onEvent = { [weak self] in self?.events.append($0) }
        driver.onExit = { [weak self] code in
            self?.didExit = true
            self?.exitCode = code
        }
    }

    var textDeltas: [String] {
        events.compactMap { event in
            if case .textDelta(_, let delta) = event { return delta }
            return nil
        }
    }

    var pendingDialogID: String? {
        for case .dialogRequested(let dialog) in events { return dialog.id }
        return nil
    }
}

/// Polls on the main actor; the fake paces its output in tens of milliseconds, so a short poll is enough.
@MainActor
func waitUntil(timeout: Duration = .seconds(10), _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

@MainActor
func thrownError(_ work: @MainActor () async throws -> Void) async -> Error? {
    do {
        try await work()
        return nil
    } catch {
        return error
    }
}
