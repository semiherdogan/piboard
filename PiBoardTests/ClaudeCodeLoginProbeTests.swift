import Testing
@testable import PiBoard
import Foundation

@MainActor
struct ClaudeCodeLoginProbeTests {
    private let executable = URL(fileURLWithPath: "/usr/local/bin/claude")

    @Test func parsesLoggedInWithMethod() {
        let state = ClaudeCodeLoginProbe.parse(#"{"loggedIn": true, "authMethod": "claude.ai", "apiProvider": "firstParty"}"#)
        #expect(state == .loggedIn(method: "claude.ai"))
    }

    @Test func parsesLoggedOut() {
        #expect(ClaudeCodeLoginProbe.parse(#"{"loggedIn": false}"#) == .loggedOut)
    }

    @Test func parsingGarbageFails() {
        #expect(ClaudeCodeLoginProbe.parse("not json") == .failed)
        #expect(ClaudeCodeLoginProbe.parse(#"{"other": 1}"#) == .failed)
    }

    @Test func refreshEndsLoggedIn() async {
        let runner = StubCommandRunner { CommandResult(exitCode: 0, stdout: #"{"loggedIn":true,"authMethod":"claude.ai"}"#, stderr: "", timedOut: false) }
        let probe = ClaudeCodeLoginProbe(runner: runner, environment: [:])

        probe.refresh(executable: executable)
        await probe.refreshTask?.value

        #expect(probe.state == .loggedIn(method: "claude.ai"))
        #expect(runner.callCount == 1)
    }

    @Test func refreshFailsWhenTheRunnerCannotLaunch() async {
        let probe = ClaudeCodeLoginProbe(runner: StubCommandRunner { nil }, environment: [:])

        probe.refresh(executable: executable)
        await probe.refreshTask?.value

        #expect(probe.state == .failed)
    }
}
