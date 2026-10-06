import Testing
@testable import PiBoard
import Foundation

@MainActor
struct PiRuntimeManagerTests {
    @Test func refreshYieldsMissingWithNoCurrentPointer() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = PiRuntimeManager(paths: PiRuntimePaths(root: root))
        manager.refresh()

        #expect(manager.status == .missing)
    }

    @Test func refreshYieldsReadyWhenEntryExists() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = PiRuntimePaths(root: root)
        let version = "1.0.4"
        let entry = paths.piEntry(for: version)
        try FileManager.default.createDirectory(at: entry.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: entry.path, contents: nil)

        try FileManager.default.createDirectory(
            at: paths.currentPointerFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let pointerData = try JSONEncoder().encode(CurrentPointer(activeVersion: version))
        try pointerData.write(to: paths.currentPointerFile)

        let manager = PiRuntimeManager(paths: paths)
        manager.refresh()

        #expect(manager.status == .ready(version: version))
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
