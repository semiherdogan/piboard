import Foundation
import Synchronization

struct CommandResult: Sendable, Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool
    let cancelled: Bool

    init(exitCode: Int32, stdout: String, stderr: String, timedOut: Bool, cancelled: Bool = false) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
        self.cancelled = cancelled
    }
}

/// Lets a caller stop a blocking `CommandRunning.run` from another task. The runner installs
/// the kill once the child has a pid; a cancel that arrives earlier is remembered and applied
/// as soon as it starts.
final class CommandCancellation: Sendable {
    private struct State {
        var terminate: (@Sendable () -> Void)?
        var isCancelled = false
    }

    private let state = Mutex(State())

    init() {}

    func cancel() {
        let terminate = state.withLock { state -> (@Sendable () -> Void)? in
            state.isCancelled = true
            return state.terminate
        }
        terminate?()
    }

    /// Called by the runner; runs `terminate` immediately when cancel already happened.
    func onStart(_ terminate: @escaping @Sendable () -> Void) {
        let runNow = state.withLock { state -> Bool in
            state.terminate = terminate
            return state.isCancelled
        }
        if runNow {
            terminate()
        }
    }
}

/// Blocking command execution for runtime install, verification and login shell resolution.
/// Callers run it off the main actor; tests inject a fake so no child process is spawned.
protocol CommandRunning: Sendable {
    /// Returns nil when the executable could not be launched.
    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration?,
        cancellation: CommandCancellation?
    ) -> CommandResult?
}

extension CommandRunning {
    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration?
    ) -> CommandResult? {
        run(executable: executable, arguments: arguments, environment: environment, timeout: timeout, cancellation: nil)
    }
}

struct ProcessCommandRunner: CommandRunning {
    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration?,
        cancellation: CommandCancellation?
    ) -> CommandResult? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        let pid = process.processIdentifier
        let cancelled = SharedValue(false)
        cancellation?.onStart {
            cancelled.set(true)
            kill(pid, SIGTERM)
        }

        let timedOut = SharedValue(false)
        let timeoutWork = timeout.map { timeout in
            let work = DispatchWorkItem {
                timedOut.set(true)
                kill(pid, SIGTERM)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout.timeInterval, execute: work)
            return work
        }

        // Both pipes are drained concurrently so neither can fill and stall the child.
        let stderrData = SharedValue(Data())
        let stderrDrained = DispatchGroup()
        let stderrHandle = stderrPipe.fileHandleForReading
        DispatchQueue.global().async(group: stderrDrained) {
            stderrData.set(stderrHandle.readDataToEndOfFile())
        }
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        stderrDrained.wait()
        process.waitUntilExit()
        timeoutWork?.cancel()

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData.get(), as: UTF8.self),
            timedOut: timedOut.get(),
            cancelled: cancelled.get()
        )
    }
}

// `Mutex` is noncopyable, so escaping closures share it through a reference.
private final class SharedValue<Value: Sendable>: Sendable {
    private let storage: Mutex<Value>

    init(_ value: Value) {
        storage = Mutex(value)
    }

    func get() -> Value {
        storage.withLock { $0 }
    }

    func set(_ value: Value) {
        storage.withLock { $0 = value }
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
