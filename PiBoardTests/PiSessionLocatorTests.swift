import Foundation
import Testing
@testable import PiBoard

struct PiSessionLocatorTests {
    private static let sessionFilePrefix = "2026-10-06T13-02-02-447Z_"
    private static let sessionFileExtension = ".jsonl"

    @Test func sessionsDirectoryEncodesCwdLikePi() {
        let agentDir = URL(fileURLWithPath: "/tmp/agent", isDirectory: true)
        let cwd = URL(fileURLWithPath: "/Users/semih/Code/otp-backend", isDirectory: true)

        let directory = PiSessionLocator.sessionsDirectory(agentDir: agentDir, cwd: cwd)

        #expect(directory.lastPathComponent == "--Users-semih-Code-otp-backend--")
        #expect(directory.deletingLastPathComponent() == PiSessionLocator.sessionsRoot(agentDir: agentDir))
    }

    @Test func agentDirectoryHonorsEnvironmentOverride() {
        let override = "/tmp/custom-agent"
        let resolved = PiSessionLocator.defaultAgentDirectory(environment: [PiSessionLocator.agentDirectoryEnvironmentKey: override])

        #expect(resolved.path == override)
    }

    @Test func sessionFileIsFoundCaseInsensitively() throws {
        let agentDir = try makeTempDirectory()
        let cwd = try makeTempDirectory()
        defer { remove(agentDir, cwd) }
        let sessionID = UUID()
        try writeSessionFile(named: Self.sessionFilePrefix + sessionID.uuidString.lowercased() + Self.sessionFileExtension, agentDir: agentDir, cwd: cwd)

        #expect(PiSessionLocator.sessionFileExists(sessionID: sessionID, cwd: cwd, agentDir: agentDir))
    }

    @Test func sessionFileReturnsTheMatchingURL() throws {
        let agentDir = try makeTempDirectory()
        let cwd = try makeTempDirectory()
        defer { remove(agentDir, cwd) }
        let sessionID = UUID()
        let name = Self.sessionFilePrefix + sessionID.uuidString.lowercased() + Self.sessionFileExtension
        try writeSessionFile(named: name, agentDir: agentDir, cwd: cwd)

        let file = PiSessionLocator.sessionFile(sessionID: sessionID, cwd: cwd, agentDir: agentDir)

        #expect(file == PiSessionLocator.sessionsDirectory(agentDir: agentDir, cwd: cwd).appendingPathComponent(name))
    }

    @Test func sessionFileReturnsNilWhenNothingMatches() throws {
        let agentDir = try makeTempDirectory()
        let cwd = try makeTempDirectory()
        defer { remove(agentDir, cwd) }
        try writeSessionFile(named: Self.sessionFilePrefix + UUID().uuidString + Self.sessionFileExtension, agentDir: agentDir, cwd: cwd)

        #expect(PiSessionLocator.sessionFile(sessionID: UUID(), cwd: cwd, agentDir: agentDir) == nil)
    }

    @Test func otherSessionFileDoesNotMatch() throws {
        let agentDir = try makeTempDirectory()
        let cwd = try makeTempDirectory()
        defer { remove(agentDir, cwd) }
        try writeSessionFile(named: Self.sessionFilePrefix + UUID().uuidString + Self.sessionFileExtension, agentDir: agentDir, cwd: cwd)

        #expect(PiSessionLocator.sessionFileExists(sessionID: UUID(), cwd: cwd, agentDir: agentDir) == false)
    }

    @Test func sessionFileUnderAnotherProjectDirectoryIsFound() throws {
        let agentDir = try makeTempDirectory()
        let cwd = try makeTempDirectory()
        let otherCwd = try makeTempDirectory()
        defer { remove(agentDir, cwd, otherCwd) }
        let sessionID = UUID()
        try writeSessionFile(named: Self.sessionFilePrefix + sessionID.uuidString + Self.sessionFileExtension, agentDir: agentDir, cwd: otherCwd)

        #expect(PiSessionLocator.sessionFileExists(sessionID: sessionID, cwd: cwd, agentDir: agentDir))
    }

    /// The locator alone cannot tell "missing" from "stored elsewhere"; the resume path treats
    /// a missing directory as unknown (see `PiProcessManagerTests`).
    @Test func missingSessionsDirectoryReportsNotFound() throws {
        let agentDir = try makeTempDirectory()
        let cwd = try makeTempDirectory()
        defer { remove(agentDir, cwd) }

        #expect(ProjectPathService.exists(PiSessionLocator.sessionsDirectory(agentDir: agentDir, cwd: cwd)) == false)
        #expect(PiSessionLocator.sessionFileExists(sessionID: UUID(), cwd: cwd, agentDir: agentDir) == false)
    }

    private func writeSessionFile(named name: String, agentDir: URL, cwd: URL) throws {
        let directory = PiSessionLocator.sessionsDirectory(agentDir: agentDir, cwd: cwd)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent(name))
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func remove(_ urls: URL...) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
