import Testing
@testable import PiBoard

@MainActor
struct PTYSessionTests {
    @Test func runsProcessAndCapturesExitCodeAndOutput() async throws {
        let session = PTYSession()
        session.start(executable: "/bin/sh", args: ["-c", "printf hello-pty; exit 3"], currentDirectory: nil)

        var attempts = 0
        while session.state != .exited(3), attempts < 50 {
            try await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }

        #expect(session.state == .exited(3))
        #expect(session.receivedBytes > 0)
    }

    @Test func terminateForceKillsAProcessThatIgnoresSIGTERM() async throws {
        let session = PTYSession(gracefulStopTimeout: 0.3)
        session.start(executable: "/bin/sh", args: ["-c", "trap '' TERM; sleep 30"], currentDirectory: nil)

        var startAttempts = 0
        while session.state != .running, startAttempts < 50 {
            try await Task.sleep(nanoseconds: 100_000_000)
            startAttempts += 1
        }

        session.terminate()

        var attempts = 0
        while !isExited(session.state), attempts < 30 {
            try await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }

        #expect(isExited(session.state))
    }

    @Test func terminateExitsPromptlyViaSIGTERMWhenNotIgnored() async throws {
        let session = PTYSession(gracefulStopTimeout: 5.0)
        session.start(executable: "/bin/sh", args: ["-c", "sleep 30"], currentDirectory: nil)

        var startAttempts = 0
        while session.state != .running, startAttempts < 50 {
            try await Task.sleep(nanoseconds: 100_000_000)
            startAttempts += 1
        }

        session.terminate()

        var attempts = 0
        while !isExited(session.state), attempts < 30 {
            try await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }

        #expect(isExited(session.state))
    }

    /// Regression test for the first-launch black terminal bug: the pty must get a sane
    /// window size even when started before the terminal view has ever had a real frame.
    @Test func reportsNonZeroWindowSizeWhenStartedBeforeViewHasAFrame() async throws {
        let session = PTYSession()
        #expect(session.terminalView.frame == .zero)
        session.start(executable: "/bin/sh", args: ["-c", "stty size; exit 0"], currentDirectory: nil)

        var attempts = 0
        while !isExited(session.state), attempts < 50 {
            try await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }

        #expect(isExited(session.state))
        let terminal = session.terminalView.getTerminal()
        let lines = (0..<terminal.rows).compactMap { terminal.getLine(row: $0)?.translateToString(trimRight: true) }
        let output = lines.joined(separator: "\n")
        #expect(output.contains("25 80"))
    }

    private func isExited(_ state: PTYRuntimeState) -> Bool {
        if case .exited = state { return true }
        return false
    }
}
