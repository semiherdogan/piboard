import Foundation
import Testing
@testable import PiBoard

struct LaunchEnvironmentTests {
    private let begin = "__BEGIN__"
    private let end = "__END__"

    private func fenced(_ entries: [String]) -> String {
        begin + entries.joined(separator: "\0") + end
    }

    @Test func parsesVariablesBetweenMarkers() {
        let parsed = LaunchEnvironment.parse(fenced(["PATH=/opt/bin:/usr/bin", "HOME=/Users/x"]), begin: begin, end: end)
        #expect(parsed?["PATH"] == "/opt/bin:/usr/bin")
        #expect(parsed?["HOME"] == "/Users/x")
    }

    @Test func ignoresStartupFileNoiseOutsideMarkers() {
        let output = "Welcome to zsh\n" + fenced(["PATH=/opt/bin"]) + "\nsome trailing banner"
        #expect(LaunchEnvironment.parse(output, begin: begin, end: end)?["PATH"] == "/opt/bin")
    }

    @Test func keepsValuesContainingEqualsSigns() {
        let parsed = LaunchEnvironment.parse(fenced(["LS_COLORS=di=1:ln=2"]), begin: begin, end: end)
        #expect(parsed?["LS_COLORS"] == "di=1:ln=2")
    }

    @Test func dropsValuesDescribingTheResolverShell() {
        let parsed = LaunchEnvironment.parse(fenced(["PWD=/tmp", "OLDPWD=/", "SHLVL=2", "_=/usr/bin/env", "PATH=/opt/bin"]), begin: begin, end: end)
        #expect(parsed?.keys.sorted() == ["PATH"])
    }

    @Test func returnsNilWhenMarkersAreMissingOrEmpty() {
        #expect(LaunchEnvironment.parse("PATH=/opt/bin", begin: begin, end: end) == nil)
        #expect(LaunchEnvironment.parse(begin + "PATH=/opt/bin", begin: begin, end: end) == nil)
        #expect(LaunchEnvironment.parse(fenced([]), begin: begin, end: end) == nil)
    }

    @Test func resolveAsksTheLoginShellInteractively() {
        let runner = RecordingRunner { arguments in
            CommandResult(exitCode: 0, stdout: "", stderr: "", timedOut: false)
        }
        _ = LaunchEnvironment.resolve(runner: runner, shell: "/bin/zsh", inherited: [:])
        #expect(runner.arguments.first?.prefix(3) == ["-l", "-i", "-c"])
    }

    @Test func inheritsWhenTheLoginShellFails() {
        let inherited = ["PATH": "/usr/bin"]
        for failure in [
            CommandResult(exitCode: 1, stdout: "", stderr: "boom", timedOut: false),
            CommandResult(exitCode: 0, stdout: "", stderr: "", timedOut: true),
        ] {
            let resolved = LaunchEnvironment.resolveOrInherit(
                runner: RecordingRunner { _ in failure },
                shell: "/bin/zsh",
                inherited: inherited
            )
            #expect(resolved.values == inherited)
        }
    }

    @Test func inheritsWhenTheShellCannotBeLaunched() {
        let inherited = ["PATH": "/usr/bin"]
        let resolved = LaunchEnvironment.resolveOrInherit(
            runner: RecordingRunner { _ in nil },
            shell: "/bin/zsh",
            inherited: inherited
        )
        #expect(resolved.values == inherited)
    }

    @Test func shellValuesOverlayTheInheritedEnvironment() {
        let runner = RecordingRunner { arguments in
            // The markers are generated per call, so they are read back out of the command.
            let markers = (arguments.last ?? "")
                .split(separator: "'")
                .filter { $0.hasPrefix("__PIBOARD_ENV_") }
            return CommandResult(
                exitCode: 0,
                stdout: markers[0] + "PATH=/opt/homebrew/bin:/usr/bin\0EDITOR=nvim" + markers[1],
                stderr: "",
                timedOut: false
            )
        }
        let resolved = LaunchEnvironment.resolveOrInherit(
            runner: runner,
            shell: "/bin/zsh",
            inherited: ["PATH": "/usr/bin", "TMPDIR": "/var/tmp"]
        )
        #expect(resolved.values["PATH"] == "/opt/homebrew/bin:/usr/bin")
        #expect(resolved.values["TMPDIR"] == "/var/tmp")
        #expect(resolved.values["EDITOR"] == "nvim")
    }

    @Test func skipsTheLoginShellInHostedTests() {
        let runner = RecordingRunner { _ in Issue.record("the login shell must not run under XCTest"); return nil }
        let inherited = [LaunchEnvironment.testConfigurationEnvKey: "/tmp/x.xctestconfiguration", "PATH": "/usr/bin"]
        let resolved = LaunchEnvironment.resolveOrInherit(runner: runner, shell: "/bin/zsh", inherited: inherited)
        #expect(resolved.values == inherited)
    }
}

private final class RecordingRunner: CommandRunning, @unchecked Sendable {
    private let handler: @Sendable ([String]) -> CommandResult?
    private(set) var arguments: [[String]] = []

    init(handler: @escaping @Sendable ([String]) -> CommandResult?) {
        self.handler = handler
    }

    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration?,
        cancellation: CommandCancellation?
    ) -> CommandResult? {
        self.arguments.append(arguments)
        return handler(arguments)
    }
}
