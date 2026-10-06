import Foundation
import Testing
@testable import PiBoard

struct ProjectPathServiceTests {
    @Test func canonicalizeResolvesSymlinkedTmp() {
        let direct = ProjectPathService.canonicalize(URL(fileURLWithPath: "/tmp"))
        let viaPrivate = ProjectPathService.canonicalize(URL(fileURLWithPath: "/private/tmp"))

        #expect(direct == viaPrivate)
    }

    @Test func canonicalizeRemovesTrailingSlash() {
        let withSlash = ProjectPathService.canonicalize(URL(fileURLWithPath: "/tmp/"))

        #expect(withSlash.path == "/tmp")
    }

    @Test func abbreviatedReplacesHomeWithTilde() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let projectURL = home.appendingPathComponent("Developer/PiBoard")

        #expect(ProjectPathService.abbreviated(projectURL) == "~/Developer/PiBoard")
    }

    @Test func abbreviatedLeavesOtherPathsUnchanged() {
        let outsideHome = URL(fileURLWithPath: "/private/tmp/PiBoard")

        #expect(ProjectPathService.abbreviated(outsideHome) == "/private/tmp/PiBoard")
    }
}
