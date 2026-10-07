import Foundation

/// The environment PiBoard hands to every child process it spawns.
///
/// A GUI launch inherits launchd's environment, whose `PATH` is only `/usr/bin:/bin:/usr/sbin:/sbin`.
/// None of the entries a developer's shell sets up (Homebrew, version managers, `~/.local/bin`) are
/// there, so Pi, npm and git subprocesses behave differently than they do from a terminal. Asking
/// the login shell once at startup closes that gap for every spawn site at the same time.
///
/// The login shell runs interactive (`-i`) on purpose: `PATH` edits usually live in `.zshrc`, which
/// a non-interactive shell never reads.
struct LaunchEnvironment: Sendable {
    /// Set by XCTest in the hosted app; tests must not spawn the developer's login shell.
    static let testConfigurationEnvKey = "XCTestConfigurationFilePath"

    private static let resolveTimeout: Duration = .seconds(3)
    private static let markerPrefix = "__PIBOARD_ENV_"
    private static let beginMarkerSuffix = "_BEGIN__"
    private static let endMarkerSuffix = "_END__"
    private static let envExecutable = URL(fileURLWithPath: "/usr/bin/env")
    private static let nullSeparator: Character = "\0"
    private static let assignmentSeparator: Character = "="
    private static let loginFlag = "-l"
    private static let interactiveFlag = "-i"
    private static let commandFlag = "-c"
    private static let nullTerminatedFlag = "-0"
    /// Values that describe the shell that produced them, not the children we spawn. Carrying them
    /// over would point a child at the resolver's working directory or nest its shell level.
    private static let volatileKeys = ["PWD", "OLDPWD", "SHLVL", "_"]

    /// Resolved once per process. Access blocks until the login shell answers or times out, so
    /// call `prewarm()` during startup rather than letting the first spawn pay for it.
    static let shared = resolveOrInherit()

    let values: [String: String]

    /// Resolves `shared` off the main thread so the first Pi launch does not wait on `.zshrc`.
    static func prewarm() {
        Task.detached(priority: .utility) {
            _ = shared
        }
    }

    /// Falls back to the inherited environment whenever the login shell cannot be read: a missing
    /// `PATH` entry degrades behaviour, but a failed startup would not be recoverable at all.
    static func resolveOrInherit(
        runner: any CommandRunning = ProcessCommandRunner(),
        shell: String = ShellResolver.loginShell(),
        inherited: [String: String] = ProcessInfo.processInfo.environment
    ) -> LaunchEnvironment {
        guard inherited[testConfigurationEnvKey] == nil else {
            return LaunchEnvironment(values: inherited)
        }
        guard let resolved = resolve(runner: runner, shell: shell, inherited: inherited) else {
            return LaunchEnvironment(values: inherited)
        }
        // launchd-only values such as TMPDIR and XPC_SERVICE_NAME are absent from a login shell,
        // so the shell's answer is layered on top of what we inherited instead of replacing it.
        return LaunchEnvironment(values: inherited.merging(resolved) { _, fromShell in fromShell })
    }

    static func resolve(
        runner: any CommandRunning,
        shell: String,
        inherited: [String: String]
    ) -> [String: String]? {
        let token = UUID().uuidString
        let begin = markerPrefix + token + beginMarkerSuffix
        let end = markerPrefix + token + endMarkerSuffix
        let command = "printf '%s' '\(begin)'; \(envExecutable.path) \(nullTerminatedFlag); printf '%s' '\(end)'"

        let result = runner.run(
            executable: URL(fileURLWithPath: shell),
            arguments: [loginFlag, interactiveFlag, commandFlag, command],
            environment: inherited,
            timeout: resolveTimeout
        )
        guard let result, !result.timedOut, result.exitCode == 0 else { return nil }
        return parse(result.stdout, begin: begin, end: end)
    }

    /// Startup files print banners and completion noise, so the variables are fenced by markers
    /// rather than assuming the output starts at the first byte.
    static func parse(_ output: String, begin: String, end: String) -> [String: String]? {
        guard let beginRange = output.range(of: begin),
              let endRange = output.range(of: end, range: beginRange.upperBound..<output.endIndex)
        else { return nil }

        var values: [String: String] = [:]
        for entry in output[beginRange.upperBound..<endRange.lowerBound].split(separator: nullSeparator) {
            guard let split = entry.firstIndex(of: assignmentSeparator) else { continue }
            let key = String(entry[entry.startIndex..<split])
            guard !key.isEmpty, !volatileKeys.contains(key) else { continue }
            values[key] = String(entry[entry.index(after: split)...])
        }
        return values.isEmpty ? nil : values
    }
}
