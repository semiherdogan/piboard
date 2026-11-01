import Foundation
import Testing
@testable import PiBoard

struct PigSubagentCompatTests {
    private let cacheRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("pig-compat-\(UUID().uuidString)")

    private func cell(_ name: String, withHarness: Bool) throws -> URL {
        let runtime = cacheRoot.appendingPathComponent("cells/node/\(name)/runtime")
        let harness = runtime.appendingPathComponent("harness")
        try FileManager.default.createDirectory(at: harness, withIntermediateDirectories: true)
        if withHarness {
            try Data("export {};\n".utf8).write(to: harness.appendingPathComponent("cli.mjs"))
        }
        return runtime
    }

    @Test func writesTheForwarderForACellWithTheHarness() throws {
        defer { try? FileManager.default.removeItem(at: cacheRoot) }
        let runtime = try cell("abc", withHarness: true)
        let forwarder = runtime.appendingPathComponent("dist/cli.js")

        let written = PigSubagentCompat.ensureForwarders(cacheRoot: cacheRoot)

        #expect(written.map { $0.resolvingSymlinksInPath().path } == [forwarder.resolvingSymlinksInPath().path])
        #expect(try String(contentsOf: forwarder, encoding: .utf8) == PigSubagentCompat.forwarderSource)
    }

    @Test func neverOverwritesAnExistingFile() throws {
        defer { try? FileManager.default.removeItem(at: cacheRoot) }
        let runtime = try cell("abc", withHarness: true)
        let forwarder = runtime.appendingPathComponent("dist/cli.js")
        try FileManager.default.createDirectory(at: forwarder.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("shipped by PiG\n".utf8)
        try original.write(to: forwarder)

        let written = PigSubagentCompat.ensureForwarders(cacheRoot: cacheRoot)

        #expect(written.isEmpty)
        #expect(try Data(contentsOf: forwarder) == original)
    }

    @Test func skipsACellWithoutTheHarness() throws {
        defer { try? FileManager.default.removeItem(at: cacheRoot) }
        let runtime = try cell("abc", withHarness: false)

        let written = PigSubagentCompat.ensureForwarders(cacheRoot: cacheRoot)

        #expect(written.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: runtime.appendingPathComponent("dist").path))
    }

    @Test func aMissingCacheRootWritesNothing() {
        #expect(PigSubagentCompat.ensureForwarders(cacheRoot: cacheRoot).isEmpty)
    }
}
