import Foundation
import Testing
@testable import PiBoard

@MainActor
struct LiveProcessRegistryTests {
    private static let sleepExecutable = URL(fileURLWithPath: "/bin/sleep")
    private static let sleepSeconds = "30"
    private static let trueExecutable = URL(fileURLWithPath: "/usr/bin/true")
    private static let fakeNodeExecutable = "/tmp/piboard-tests/node/bin/node"

    @Test func entriesRoundTripThroughFile() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("runtime/live-processes.json")
        let first = makeEntry(pid: 101)
        let second = makeEntry(pid: 102)

        let registry = LiveProcessRegistry(fileURL: fileURL)
        registry.add(first)
        registry.add(second)

        #expect(LiveProcessRegistry(fileURL: fileURL).entries == [first, second])
    }

    @Test func fileParsesAfterWrite() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("live-processes.json")
        let entry = makeEntry(pid: 201)

        LiveProcessRegistry(fileURL: fileURL).add(entry)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([LiveProcessEntry].self, from: Data(contentsOf: fileURL))
        #expect(decoded == [entry])
    }

    @Test func removeDropsEntryAndDeletesEmptyFile() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("live-processes.json")
        let kept = makeEntry(pid: 301)
        let exited = makeEntry(pid: 302)
        let registry = LiveProcessRegistry(fileURL: fileURL)
        registry.add(kept)
        registry.add(exited)

        registry.remove(pid: exited.pid)
        #expect(LiveProcessRegistry(fileURL: fileURL).entries == [kept])

        registry.remove(pid: kept.pid)
        #expect(registry.entries.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    @Test func liveChildMatchesUntilTerminated() throws {
        let startedAt = Date()
        let process = Process()
        process.executableURL = Self.sleepExecutable
        process.arguments = [Self.sleepSeconds]
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
            }
        }
        let entry = LiveProcessEntry(
            pid: process.processIdentifier,
            taskID: UUID(),
            startedAt: startedAt,
            executablePath: Self.sleepExecutable.path
        )

        #expect(ProcessInspector.isAlive(pid: entry.pid))
        #expect(ProcessInspector.isSameProcess(entry))
        // Still parented to the test host, so it is not left over from a crash.
        #expect(OrphanedProcessCleanup.orphans(in: [entry], expectedExecutable: Self.sleepExecutable).isEmpty)

        process.terminate()
        process.waitUntilExit()

        #expect(ProcessInspector.isAlive(pid: entry.pid) == false)
        #expect(ProcessInspector.isSameProcess(entry) == false)
    }

    @Test func deadPidIsNotAnOrphan() throws {
        let process = Process()
        process.executableURL = Self.trueExecutable
        try process.run()
        process.waitUntilExit()
        let entry = LiveProcessEntry(
            pid: process.processIdentifier,
            taskID: UUID(),
            startedAt: Date(),
            executablePath: Self.fakeNodeExecutable
        )

        let orphans = OrphanedProcessCleanup.orphans(
            in: [entry],
            expectedExecutable: URL(fileURLWithPath: Self.fakeNodeExecutable)
        )

        #expect(orphans.isEmpty)
    }

    private func makeEntry(pid: Int32) -> LiveProcessEntry {
        // Whole seconds so the ISO 8601 round trip is lossless.
        LiveProcessEntry(
            pid: pid,
            taskID: UUID(),
            startedAt: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)),
            executablePath: Self.fakeNodeExecutable
        )
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
