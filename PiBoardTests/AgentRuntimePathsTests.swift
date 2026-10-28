import Testing
@testable import PiBoard
import Foundation

struct AgentRuntimePathsTests {
    private let fakePackage = AgentPackage(
        kind: .pi,
        npmName: "opencode-ai",
        entry: .binary(relativePath: "bin/opencode"),
        runtimeFolderName: "opencode",
        installation: .managed
    )

    @Test func entryPathForVersion() {
        let root = URL(fileURLWithPath: "/tmp/piboard-test-root")
        let paths = AgentRuntimePaths(root: root)

        let expected = root
            .appendingPathComponent("runtime/pi/versions/1.0.4/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js")
        #expect(paths.entry(for: "1.0.4") == expected)
    }

    @Test func currentPointerFilePath() {
        let root = URL(fileURLWithPath: "/tmp/piboard-test-root")
        let paths = AgentRuntimePaths(root: root)

        #expect(paths.currentPointerFile == root.appendingPathComponent("runtime/pi/current.json"))
    }

    @Test func binaryEntryResolvesUnderNodeModules() {
        let root = URL(fileURLWithPath: "/tmp/piboard-test-root")
        let paths = AgentRuntimePaths(package: fakePackage, root: root)

        let expected = root.appendingPathComponent("runtime/opencode/versions/1.2.3/node_modules/opencode-ai/bin/opencode")
        #expect(paths.entry(for: "1.2.3") == expected)
    }

    @Test func runtimeFoldersAreSeparatePerPackage() {
        let root = URL(fileURLWithPath: "/tmp/piboard-test-root")
        let pi = AgentRuntimePaths(package: .pi, root: root)
        let other = AgentRuntimePaths(package: fakePackage, root: root)

        #expect(pi.versionsDirectory != other.versionsDirectory)
        #expect(pi.npmCacheDirectory == other.npmCacheDirectory)
    }
}
