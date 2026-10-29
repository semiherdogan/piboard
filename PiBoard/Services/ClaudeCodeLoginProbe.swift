import Foundation
import Observation

/// Asks `claude auth status` whether the user is signed in. Informational only: a launch still works
/// and Claude Code shows its own login prompt in the terminal.
@MainActor
@Observable
final class ClaudeCodeLoginProbe {
    enum State: Equatable, Sendable {
        case unknown
        case checking
        case loggedIn(method: String?)
        case loggedOut
        case failed
    }

    nonisolated static let authArguments = ["auth", "status"]
    nonisolated static let timeout: Duration = .seconds(10)
    private nonisolated static let loggedInKey = "loggedIn"
    private nonisolated static let authMethodKey = "authMethod"

    private(set) var state: State = .unknown
    /// Exposed so tests can await a refresh.
    private(set) var refreshTask: Task<Void, Never>?

    @ObservationIgnored private let runner: any CommandRunning
    @ObservationIgnored private let environment: [String: String]

    init(runner: any CommandRunning = ProcessCommandRunner(), environment: [String: String] = LaunchEnvironment.shared.values) {
        self.runner = runner
        self.environment = environment
    }

    func refresh(executable: URL) {
        guard state != .checking else { return }
        state = .checking
        let runner = runner
        let environment = environment
        refreshTask = Task {
            let result = await Task.detached(priority: .utility) {
                Self.probe(runner: runner, executable: executable, environment: environment)
            }.value
            state = result
        }
    }

    // Blocking: runs the CLI, so it must stay off the main actor.
    private nonisolated static func probe(runner: any CommandRunning, executable: URL, environment: [String: String]) -> State {
        guard let result = runner.run(executable: executable, arguments: authArguments, environment: environment, timeout: timeout),
              !result.timedOut else { return .failed }
        return parse(result.stdout)
    }

    /// Visible for tests: `{"loggedIn": true, "authMethod": "claude.ai", ...}`.
    nonisolated static func parse(_ output: String) -> State {
        guard let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let loggedIn = object[loggedInKey] as? Bool else { return .failed }
        return loggedIn ? .loggedIn(method: object[authMethodKey] as? String) : .loggedOut
    }
}
