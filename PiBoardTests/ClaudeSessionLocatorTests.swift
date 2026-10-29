import Foundation
import Testing
@testable import PiBoard

struct ClaudeSessionLocatorTests {
    private let sessionID = "0b0c7f0e-1c2d-4e5f-8a9b-0c1d2e3f4a5b"

    @Test func encodedNameReplacesSlashesAndDots() {
        let cwd = URL(fileURLWithPath: "/nonexistent-root/my.project/sub")

        #expect(ClaudeSessionLocator.encodedProjectName(cwd: cwd) == "-nonexistent-root-my-project-sub")
    }

    @Test func findsTheFileInTheEncodedFolder() throws {
        let projects = try makeProjects()
        defer { try? FileManager.default.removeItem(at: projects) }
        let cwd = URL(fileURLWithPath: "/nonexistent-root/my.project")
        let folder = projects.appendingPathComponent(ClaudeSessionLocator.encodedProjectName(cwd: cwd))
        let file = try writeSession(in: folder)

        let found = ClaudeSessionLocator.sessionFile(sessionID: sessionID, cwd: cwd, projectsDirectory: projects)

        #expect(found == file)
    }

    @Test func findsTheFileInAnotherProjectFolder() throws {
        let projects = try makeProjects()
        defer { try? FileManager.default.removeItem(at: projects) }
        let file = try writeSession(in: projects.appendingPathComponent("-other-project"))

        let found = ClaudeSessionLocator.sessionFile(
            sessionID: sessionID.uppercased(),
            cwd: URL(fileURLWithPath: "/nonexistent-root/elsewhere"),
            projectsDirectory: projects
        )

        #expect(found == file)
    }

    @Test func returnsNilWhenAbsent() throws {
        let projects = try makeProjects()
        defer { try? FileManager.default.removeItem(at: projects) }
        try FileManager.default.createDirectory(at: projects.appendingPathComponent("-other-project"), withIntermediateDirectories: true)

        let found = ClaudeSessionLocator.sessionFile(
            sessionID: sessionID,
            cwd: URL(fileURLWithPath: "/nonexistent-root/x"),
            projectsDirectory: projects
        )

        #expect(found == nil)
    }

    @Test func returnsNilForANonUUID() throws {
        let projects = try makeProjects()
        defer { try? FileManager.default.removeItem(at: projects) }

        let found = ClaudeSessionLocator.sessionFile(
            sessionID: "not-a-uuid",
            cwd: URL(fileURLWithPath: "/nonexistent-root/x"),
            projectsDirectory: projects
        )

        #expect(found == nil)
    }

    @Test func defaultProjectsDirectoryIsUnderTheHome() {
        let home = URL(fileURLWithPath: "/nonexistent-home")

        #expect(ClaudeSessionLocator.defaultProjectsDirectory(home: home).path == "/nonexistent-home/.claude/projects")
    }

    private func makeProjects() throws -> URL {
        let projects = FileManager.default.temporaryDirectory.appendingPathComponent("piboard-claude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        return projects
    }

    private func writeSession(in folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("\(sessionID).jsonl")
        try Data().write(to: file)
        return file
    }
}
