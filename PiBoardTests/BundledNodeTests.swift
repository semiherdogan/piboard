import Testing
@testable import PiBoard
import Foundation

struct BundledNodeTests {
    @Test func throwsOnEmptyRoot() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: BundledNodeError.self) {
            try BundledNode.locate(root: root)
        }
    }

    @Test func succeedsWhenPlaceholdersExist() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let nodeExecutable = root.appendingPathComponent("node/bin/node")
        let npmCLI = root.appendingPathComponent("node/lib/node_modules/npm/bin/npm-cli.js")

        try FileManager.default.createDirectory(
            at: nodeExecutable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: npmCLI.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: nodeExecutable.path, contents: nil)
        FileManager.default.createFile(atPath: npmCLI.path, contents: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: nodeExecutable.path)

        let bundledNode = try BundledNode.locate(root: root)
        #expect(bundledNode.nodeExecutable == nodeExecutable)
        #expect(bundledNode.npmCLI == npmCLI)
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
