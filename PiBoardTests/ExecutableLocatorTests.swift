import Testing
@testable import PiBoard
import Foundation

struct ExecutableLocatorTests {
    private let home = URL(fileURLWithPath: "/home/me")
    private let name = "opencode"

    @Test func knownPathWinsOverPATH() {
        let known = "/opt/known/opencode"
        let found = ExecutableLocator.locate(
            executableName: name,
            knownPaths: [known],
            pathVariable: "/a",
            home: home,
            isExecutable: { _ in true }
        )
        #expect(found == URL(fileURLWithPath: known))
    }

    @Test func tildeIsExpandedAgainstHome() {
        let expected = home.appendingPathComponent(".opencode/bin/opencode")
        let found = ExecutableLocator.locate(
            executableName: name,
            knownPaths: ["~/.opencode/bin/opencode"],
            pathVariable: nil,
            home: home,
            isExecutable: { $0 == expected }
        )
        #expect(found == expected)
    }

    @Test func fallsBackToPATHEntries() {
        let expected = URL(fileURLWithPath: "/b/opencode")
        let found = ExecutableLocator.locate(
            executableName: name,
            knownPaths: ["~/.opencode/bin/opencode"],
            pathVariable: "/a:/b",
            home: home,
            isExecutable: { $0 == expected }
        )
        #expect(found == expected)
    }

    @Test func nilWhenNothingIsExecutable() {
        let found = ExecutableLocator.locate(
            executableName: name,
            knownPaths: ["~/.opencode/bin/opencode"],
            pathVariable: "/a:/b",
            home: home,
            isExecutable: { _ in false }
        )
        #expect(found == nil)
    }

    @Test func parseVersionStripsThePrefix() {
        #expect(ExecutableLocator.parseVersion("opencode v2.2.0\n") == "2.2.0")
    }

    @Test func parseVersionSkipsTrailingProductName() {
        #expect(ExecutableLocator.parseVersion("2.1.294 (Claude Code)\n") == "2.1.294")
    }

    @Test func parseVersionWithoutPrefix() {
        #expect(ExecutableLocator.parseVersion("2.2.0") == "2.2.0")
    }

    @Test func parseVersionIgnoresGarbage() {
        #expect(ExecutableLocator.parseVersion("command not found") == nil)
    }
}
