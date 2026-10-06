import Foundation
import Testing
@testable import PiBoard

struct AppEnvironmentRecoveryTests {
    private static let databaseFileName = "piboard.sqlite"
    private static let corruptMarker = ".corrupt-"
    private static let sidecarSuffixes = ["-wal", "-shm"]
    private static let garbageByte: UInt8 = 0xAB
    private static let garbageSize = 4096

    @Test func freshPathOpensWithoutNote() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let (database, note) = AppEnvironment.openOrRecover(at: directory.appendingPathComponent(Self.databaseFileName))

        #expect(note == nil)
        #expect(database.perform { $0.userVersion } == MigrationRunner.all.last!.version)
    }

    @Test func corruptFileIsMovedAsideAndReplaced() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(Self.databaseFileName)
        let garbage = Data(repeating: Self.garbageByte, count: Self.garbageSize)
        try garbage.write(to: url)

        let (database, note) = AppEnvironment.openOrRecover(at: url)

        #expect(database.perform { $0.userVersion } == MigrationRunner.all.last!.version)
        let backup = try #require(movedFile(named: Self.databaseFileName, in: directory))
        #expect(try Data(contentsOf: backup) == garbage)
        let recoveryNote = try #require(note)
        #expect(recoveryNote.contains(backup.path))
    }

    @Test func corruptSidecarsAreMovedToo() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(Self.databaseFileName)
        let garbage = Data(repeating: Self.garbageByte, count: Self.garbageSize)
        try garbage.write(to: url)
        for suffix in Self.sidecarSuffixes {
            try garbage.write(to: URL(fileURLWithPath: url.path + suffix))
        }

        let (database, note) = AppEnvironment.openOrRecover(at: url)

        #expect(note != nil)
        #expect(database.perform { $0.userVersion } == MigrationRunner.all.last!.version)
        // SQLite rewrites the sidecars during the failed open, so only their move is checked.
        for suffix in Self.sidecarSuffixes {
            #expect(movedFile(named: Self.databaseFileName + suffix, in: directory) != nil)
        }
    }

    private func movedFile(named name: String, in directory: URL) -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .first { $0.hasPrefix(name + Self.corruptMarker) }
            .map { directory.appendingPathComponent($0) }
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
