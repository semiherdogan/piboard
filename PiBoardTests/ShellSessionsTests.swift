import Foundation
import Testing
@testable import PiBoard

@MainActor
struct ShellSessionsTests {
    private static let directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private static let pollAttempts = 30
    private static let pollInterval: Duration = .milliseconds(100)

    /// Runs `/bin/sh -c <script>` instead of the user's login shell so tests are fast and deterministic.
    private func makeShells(script: String) -> ShellSessions {
        ShellSessions(makeSession: { PTYSession() }, start: { session, directory in
            session.start(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script], currentDirectory: directory)
        })
    }

    private func wait(until condition: () -> Bool) async throws {
        var attempts = 0
        while !condition(), attempts < Self.pollAttempts {
            try await Task.sleep(for: Self.pollInterval)
            attempts += 1
        }
    }

    @Test func openStartsOneShellPerProject() {
        let shells = makeShells(script: "sleep 30")
        let first = UUID()
        let second = UUID()

        let a = shells.open(projectID: first, directory: Self.directory)
        let b = shells.open(projectID: first, directory: Self.directory)
        let c = shells.open(projectID: second, directory: Self.directory)

        #expect(a === b)
        #expect(a !== c)
        shells.stopAll()
    }

    @Test func closeForgetsTheSession() async throws {
        let shells = makeShells(script: "sleep 30")
        let projectID = UUID()
        let session = shells.open(projectID: projectID, directory: Self.directory)

        shells.close(projectID: projectID)

        #expect(shells.session(for: projectID) == nil)
        try await wait { !session.state.isRunning }
        #expect(!session.state.isRunning)
    }

    @Test func forgetDropsAnExitedSession() async throws {
        let shells = makeShells(script: "exit 0")
        let projectID = UUID()
        let first = shells.open(projectID: projectID, directory: Self.directory)
        try await wait { !first.state.isRunning }
        #expect(!first.state.isRunning)

        shells.forget(projectID: projectID)
        #expect(shells.session(for: projectID) == nil)

        let second = shells.open(projectID: projectID, directory: Self.directory)
        #expect(second !== first)
    }

    @Test func openReplacesAnExitedShell() async throws {
        let shells = makeShells(script: "exit 0")
        let projectID = UUID()
        let first = shells.open(projectID: projectID, directory: Self.directory)
        try await wait { !first.state.isRunning }

        let second = shells.open(projectID: projectID, directory: Self.directory)
        #expect(second !== first)
    }

    @Test func runningCountCountsOnlyRunningShells() async throws {
        let running = makeShells(script: "sleep 30")
        _ = running.open(projectID: UUID(), directory: Self.directory)
        _ = running.open(projectID: UUID(), directory: Self.directory)
        #expect(running.runningCount == 2)

        let exited = makeShells(script: "exit 0")
        let session = exited.open(projectID: UUID(), directory: Self.directory)
        try await wait { !session.state.isRunning }
        #expect(exited.runningCount == 0)

        running.stopAll()
    }
}
