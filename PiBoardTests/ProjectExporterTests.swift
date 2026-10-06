import Foundation
import Testing
@testable import PiBoard

private let jqPath: String? = ["/usr/bin/jq", "/opt/homebrew/bin/jq"]
    .first { FileManager.default.isExecutableFile(atPath: $0) }

private let specSampleJSON = """
{
  "formatVersion": 1,
  "project": { "name": "My App", "path": "~/Developer/my-app" },
  "tasks": [ { "title": "Fix authentication", "prompt": "Investigate...", "status": "backlog", "position": 0 } ]
}
"""

@MainActor
struct ProjectExporterTests {
    private func makeModel() throws -> BoardModel {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)
        return BoardModel(database: database)
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func isMalformed(_ error: any Error) -> Bool {
        guard case .malformed = error as? ProjectExportError else { return false }
        return true
    }

    private func json(formatVersion: Int = 1, name: String = "\"App\"", path: String = "\"/tmp/app\"", status: String = "backlog") -> Data {
        Data("""
        {
          "formatVersion": \(formatVersion),
          "project": { "name": \(name), "path": \(path) },
          "tasks": [ { "title": "T", "prompt": "P", "status": "\(status)", "position": 0 } ]
        }
        """.utf8)
    }

    // Builds a project with tasks in every column plus machine-specific state on one task.
    private func makeExportableModel(path: URL) throws -> (BoardModel, Project) {
        let model = try makeModel()
        model.addProject(name: "Round Trip", path: path)
        let project = try #require(model.projects.first)
        for index in 0..<5 {
            model.addTask(title: "Task \(index)", prompt: "Prompt \(index)\nline two", to: project.id)
        }
        let backlog = model.tasks(for: project.id, status: .backlog)
        model.move(taskID: backlog[3].id, to: .inProgress, at: 0)
        model.move(taskID: backlog[1].id, to: .inProgress, at: 0)
        model.move(taskID: backlog[4].id, to: .done, at: 0)
        model.setPiSessionID(UUID(), for: backlog[1].id)
        model.setRunContext(.worktree, for: backlog[1].id)
        model.setWorktree(path: path.appendingPathComponent("wt"), branch: "piboard/x", for: backlog[1].id)
        return (model, project)
    }

    @Test func roundTripReproducesTasksWithoutMachineSpecificFields() throws {
        let folder = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (source, project) = try makeExportableModel(path: folder)

        let document = try #require(source.exportDocument(projectID: project.id))
        let data = try ProjectExporter.encode(document)
        let text = try #require(String(data: data, encoding: .utf8))
        for forbidden in ["piSessionId", "worktree", "runContext", "createdAt", "updatedAt", "\"id\"", "projectId"] {
            #expect(!text.contains(forbidden), "exported JSON must not contain \(forbidden)")
        }

        let target = try makeModel()
        let imported = try target.importProject(from: ProjectExporter.decode(data))

        #expect(imported.id != project.id)
        #expect(imported.name == project.name)
        #expect(imported.path == ProjectPathService.canonicalize(folder))
        #expect(target.selectedProjectID == imported.id)
        for status in TaskStatus.allCases {
            let expected = source.tasks(for: project.id, status: status)
            let actual = target.tasks(for: imported.id, status: status)
            #expect(actual.map(\.title) == expected.map(\.title))
            #expect(actual.map(\.prompt) == expected.map(\.prompt))
            #expect(actual.map(\.position) == Array(0..<expected.count))
            #expect(actual.allSatisfy { $0.piSessionId == nil && $0.runContext == nil && $0.worktreePath == nil && $0.worktreeBranch == nil })
        }
        #expect(Set(target.tasks.map(\.id)).isDisjoint(with: source.tasks.map(\.id)))
    }

    @Test func exportOrdersTasksByStatusThenPosition() throws {
        let (model, project) = try makeExportableModel(path: URL(fileURLWithPath: "/tmp/order"))
        let document = try #require(model.exportDocument(projectID: project.id))
        let expected = TaskStatus.allCases.flatMap { model.tasks(for: project.id, status: $0) }.map(\.title)
        #expect(document.tasks.map(\.title) == expected)
    }

    @Test func importPersistsAtomicallyAndSurvivesReload() throws {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)
        let model = BoardModel(database: database)
        let imported = try model.importProject(from: ProjectExporter.decode(Data(specSampleJSON.utf8)))

        let reloaded = BoardModel(database: database)
        #expect(reloaded.projects.map(\.id) == [imported.id])
        #expect(reloaded.tasks(for: imported.id).map(\.title) == ["Fix authentication"])
    }

    @Test func homePathIsAbbreviatedOnExportAndExpandedOnImport() throws {
        let home = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path)
        let folder = home.appendingPathComponent("Developer/piboard-missing-\(UUID().uuidString)")
        let model = try makeModel()
        model.addProject(name: "Home", path: folder)
        let project = try #require(model.projects.first)

        let document = try #require(model.exportDocument(projectID: project.id))
        #expect(document.project.path == "~/Developer/\(folder.lastPathComponent)")

        #expect(try ProjectExporter.expandedPath(document.project.path) == folder)
        #expect(try ProjectExporter.expandedPath("~") == home)
        #expect(try ProjectExporter.expandedPath("/tmp/abs") == URL(fileURLWithPath: "/tmp/abs"))
        #expect(throws: ProjectExportError.self) { try ProjectExporter.expandedPath("relative/dir") }
    }

    @Test func importOfMissingPathSucceedsAndKeepsExpandedPath() throws {
        let missing = "/tmp/piboard-missing-\(UUID().uuidString)"
        let model = try makeModel()
        let imported = try model.importProject(from: ProjectExporter.decode(json(path: "\"\(missing)\"")))
        #expect(imported.path == URL(fileURLWithPath: missing))
        #expect(!ProjectPathService.exists(imported.path))
    }

    @Test func importNormalizesPositionsPerStatusInFileOrder() throws {
        let data = Data("""
        {
          "formatVersion": 1,
          "project": { "name": "Gaps", "path": "/tmp/gaps" },
          "tasks": [
            { "title": "B1", "prompt": "", "status": "backlog", "position": 7 },
            { "title": "D1", "prompt": "", "status": "done", "position": 3 },
            { "title": "B2", "prompt": "", "status": "backlog", "position": 2 },
            { "title": "B3", "prompt": "", "status": "backlog", "position": 2 }
          ]
        }
        """.utf8)
        let model = try makeModel()
        let imported = try model.importProject(from: ProjectExporter.decode(data))

        let backlog = model.tasks(for: imported.id, status: .backlog)
        #expect(backlog.map(\.title) == ["B1", "B2", "B3"])
        #expect(backlog.map(\.position) == [0, 1, 2])
        #expect(model.tasks(for: imported.id, status: .done).map(\.position) == [0])
    }

    @Test func newerFormatVersionIsUnsupported() {
        #expect(throws: ProjectExportError.unsupportedFormatVersion(2)) {
            try ProjectExporter.decode(json(formatVersion: 2))
        }
    }

    @Test func unknownStatusIsInvalidStatus() {
        #expect(throws: ProjectExportError.invalidStatus("blocked")) {
            try ProjectExporter.decode(json(status: "blocked"))
        }
    }

    @Test func missingProjectNameIsMalformed() {
        let data = Data("""
        { "formatVersion": 1, "project": { "path": "/tmp/app" }, "tasks": [] }
        """.utf8)
        #expect { try ProjectExporter.decode(data) } throws: { isMalformed($0) }
    }

    @Test func blankProjectNameIsRejected() {
        #expect(throws: ProjectExportError.emptyProjectName) {
            try ProjectExporter.decode(json(name: "\"  \""))
        }
    }

    @Test func relativePathIsMalformed() {
        #expect { try ProjectExporter.decode(json(path: "\"Developer/app\"")) } throws: { isMalformed($0) }
    }

    @Test func nonJSONAndMissingVersionAreMalformed() {
        #expect { try ProjectExporter.decode(Data("not json".utf8)) } throws: { isMalformed($0) }
        #expect { try ProjectExporter.decode(Data("{}".utf8)) } throws: { isMalformed($0) }
    }

    @Test func specSampleDecodesExactly() throws {
        let document = try ProjectExporter.decode(Data(specSampleJSON.utf8))
        #expect(document == ProjectExportDocument(
            formatVersion: 1,
            project: .init(name: "My App", path: "~/Developer/my-app"),
            tasks: [.init(title: "Fix authentication", prompt: "Investigate...", status: .backlog, position: 0)]
        ))
    }

    @Test func encodedDocumentDecodesBackUnchanged() throws {
        let document = try ProjectExporter.decode(Data(specSampleJSON.utf8))
        let encoded = try ProjectExporter.encode(document)
        #expect(try ProjectExporter.decode(encoded) == document)
        let text = try #require(String(data: encoded, encoding: .utf8))
        #expect(text.contains("\"~/Developer/my-app\""))
    }

    @Test func importWithExistingNameCreatesSecondProject() throws {
        let model = try makeModel()
        model.addProject(name: "My App", path: URL(fileURLWithPath: "/tmp/my-app"))
        let existing = try #require(model.projects.first)

        let imported = try model.importProject(from: ProjectExporter.decode(Data(specSampleJSON.utf8)))

        #expect(model.projects.count == 2)
        #expect(imported.id != existing.id)
        #expect(model.projects.map(\.name) == ["My App", "My App"])
        #expect(model.tasks(for: existing.id).isEmpty)
    }

    @Test func defaultFileNameUsesExportExtension() {
        #expect(ProjectExportDocument.defaultFileName(for: "My App") == "My App.piboard.json")
    }

    @Test(.enabled(if: jqPath != nil, "jq is not installed"))
    func exportedFileIsValidForJQ() throws {
        let (model, project) = try makeExportableModel(path: URL(fileURLWithPath: "/tmp/jq"))
        let document = try #require(model.exportDocument(projectID: project.id))
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(ProjectExportDocument.defaultFileName(for: UUID().uuidString))
        try ProjectExporter.encode(document).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: try #require(jqPath))
        process.arguments = [".", file.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
