import Testing
@testable import PiBoard
import Foundation

struct PiRuntimePathsTests {
    @Test func entryPathForVersion() {
        let root = URL(fileURLWithPath: "/tmp/piboard-test-root")
        let paths = PiRuntimePaths(root: root)

        let expected = root
            .appendingPathComponent("runtime/pi/versions/1.0.4/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js")
        #expect(paths.piEntry(for: "1.0.4") == expected)
    }

    @Test func currentPointerFilePath() {
        let root = URL(fileURLWithPath: "/tmp/piboard-test-root")
        let paths = PiRuntimePaths(root: root)

        #expect(paths.currentPointerFile == root.appendingPathComponent("runtime/pi/current.json"))
    }
}
