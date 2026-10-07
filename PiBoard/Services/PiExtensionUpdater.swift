import Foundation

enum PiExtensionUpdatePhase: Equatable, Sendable {
    case idle
    case updating
    case succeeded(at: Date)
    case failed(reason: String)
}

struct PiExtensionUpdateOutcome: Sendable, Equatable {
    enum Result: Sendable, Equatable {
        case success
        case failure(String)
    }
    let outcome: Result
    let log: String
}

/// Runs `pi update --extensions`, which reconciles the packages declared in the user's Pi
/// settings. Kept outside `PiRuntimeManager` (and thus outside the main actor) so its blocking
/// call can run on a detached task, mirroring `PiInstallRunner`.
///
/// This never touches the Pi runtime itself: PiBoard owns which Pi version is active through its
/// own versioned installs, and `--extensions` updates packages only.
enum PiExtensionUpdater {
    private static let updateSubcommand = "update"
    private static let extensionsFlag = "--extensions"
    /// Git clones and npm installs run here, so the budget is far larger than a version check.
    static let timeout: Duration = .seconds(300)

    static func run(runner: any CommandRunning, node: BundledNode, entry: URL) -> PiExtensionUpdateOutcome {
        guard let result = runner.run(
            executable: node.nodeExecutable,
            arguments: [entry.path, updateSubcommand, extensionsFlag],
            environment: PiInstallRunner.verificationEnvironment(),
            timeout: timeout
        ) else {
            return PiExtensionUpdateOutcome(outcome: .failure("Could not launch Pi to update extensions"), log: "")
        }

        let log = PiInstallRunner.tail(result.stdout + result.stderr)
        if result.timedOut {
            return PiExtensionUpdateOutcome(outcome: .failure("Updating extensions timed out"), log: log)
        }
        guard result.exitCode == 0 else {
            return PiExtensionUpdateOutcome(outcome: .failure("Pi exited with status \(result.exitCode)"), log: log)
        }
        return PiExtensionUpdateOutcome(outcome: .success, log: log)
    }
}
