import AppKit
import UniformTypeIdentifiers

@MainActor
enum ProjectExportPanels {
    /// Returns false when the user cancels; throws when encoding or writing fails.
    @discardableResult
    static func exportProject(_ project: Project, from board: BoardModel) throws -> Bool {
        guard let document = board.exportDocument(projectID: project.id) else { return false }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = ProjectExportDocument.defaultFileName(for: project.name)
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        try ProjectExporter.encode(document).write(to: url, options: .atomic)
        return true
    }

    static func chooseImportFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    @discardableResult
    static func importProject(contentsOf url: URL, into board: BoardModel) throws -> Project {
        let data = try Data(contentsOf: url)
        return try board.importProject(from: ProjectExporter.decode(data))
    }

    static func isImportableFile(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .json) == true
    }
}
