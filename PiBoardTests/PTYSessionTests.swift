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
}
