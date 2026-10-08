import Foundation
import Observation

enum GitTerminalOutcome: Equatable, Sendable {
    /// Nil exit code means the process was killed rather than exited.
    case exited(Int32?)
    case timedOut
}

@MainActor
struct GitTerminalRun {
    let session: PTYSession
    let outcome: Task<GitTerminalOutcome, Never>
}

/// Runs git inside a pty so passphrase, host-key and credential prompts reach the user. The
/// silent `GitCommandRunner` sets GIT_TERMINAL_PROMPT=0; this path must not, which is why it
/// goes through `PTYSession` and its login-shell environment instead.
@MainActor
protocol GitTerminalRunning: AnyObject {
    /// The session is returned for display; `outcome` resolves when git exits or the timeout fires.
    func start(_ arguments: [String], in directory: URL) -> GitTerminalRun
}

@MainActor
final class GitTerminalRunner: GitTerminalRunning {
    /// Long enough for a slow remote, short enough that a hung credential helper is noticed.
    static let defaultTimeout: Duration = .seconds(120)

    private let makeSession: @MainActor () -> PTYSession
    private let timeout: Duration
    private let executable: URL

    init(
        makeSession: @escaping @MainActor () -> PTYSession,
        timeout: Duration = defaultTimeout,
        executable: URL = GitCommandRunner.defaultExecutable
    ) {
        self.makeSession = makeSession
        self.timeout = timeout
        self.executable = executable
    }

    func start(_ arguments: [String], in directory: URL) -> GitTerminalRun {
        let session = makeSession()
        session.start(executable: executable, arguments: arguments, currentDirectory: directory)
        let timeout = timeout
        let outcome = Task { @MainActor () -> GitTerminalOutcome in
            let result = await withCheckedContinuation { (continuation: CheckedContinuation<GitTerminalOutcome, Never>) in
                let race = Race(continuation)
                let exitTask = Task { @MainActor in
                    race.resume(with: .exited(await Self.waitForExit(of: session)))
                }
                let timeoutTask = Task { @MainActor in
                    // A cancelled sleep means git already exited; the resume below is then a no-op.
                    guard (try? await Task.sleep(for: timeout)) != nil else { return }
                    race.resume(with: .timedOut)
                }
                race.track(exitTask, timeoutTask)
            }
            if result == .timedOut {
                // The exit watcher still runs; terminate makes it finish within the grace period.
                session.terminate()
            }
            return result
        }
        return GitTerminalRun(session: session, outcome: outcome)
    }

    /// Resolves the continuation once with whichever outcome arrives first, then cancels the loser.
    @MainActor
    private final class Race {
        private var continuation: CheckedContinuation<GitTerminalOutcome, Never>?
        private var tasks: [Task<Void, Never>] = []

        init(_ continuation: CheckedContinuation<GitTerminalOutcome, Never>) {
            self.continuation = continuation
        }

        func track(_ tasks: Task<Void, Never>...) {
            self.tasks = tasks
        }

        func resume(with outcome: GitTerminalOutcome) {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(returning: outcome)
            tasks.forEach { $0.cancel() }
        }
    }

    /// Observation fires once per change, so re-arm until the state is an exit. The check and the
    /// registration both happen on the main actor without suspension, so no change is missed.
    private static func waitForExit(of session: PTYSession) async -> Int32? {
        while true {
            if case .exited(let code) = session.state {
                return code
            }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                withObservationTracking {
                    _ = session.state
                } onChange: {
                    continuation.resume()
                }
            }
        }
    }
}
