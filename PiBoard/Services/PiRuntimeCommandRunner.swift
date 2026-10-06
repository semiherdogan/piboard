import Foundation
import Synchronization

struct PiRuntimeCommandResult: Sendable, Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool
}

/// Blocking command execution for runtime install and verification. Callers run it off the
/// main actor; tests inject a fake so no `node` process is spawned.
protocol PiRuntimeCommandRunning: Sendable {
    /// Returns nil when the executable could not be launched.
    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration?
    ) -> PiRuntimeCommandResult?
}

struct ProcessCommandRunner: PiRuntimeCommandRunning {
    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration?
    ) -> PiRuntimeCommandResult? {
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

        let timedOut = SharedValue(false)
        let timeoutWork = timeout.map { timeout in
            let pid = process.processIdentifier
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

        return PiRuntimeCommandResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData.get(), as: UTF8.self),
            timedOut: timedOut.get()
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
