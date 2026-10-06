import Foundation

enum ProjectExporter {
    private static let homePrefix = "~"
    private static let pathSeparator = "/"

    // Read before the full decode so a newer file reports its version instead of whatever
    // shape change made the full decode fail.
    private struct VersionProbe: Decodable {
        let formatVersion: Int
    }

    static func document(project: Project, tasks: [BoardTask]) -> ProjectExportDocument {
        let statusOrder = TaskStatus.allCases
        let ordered = tasks
            .filter { $0.projectId == project.id }
            .sorted { lhs, rhs in
                let lhsRank = statusOrder.firstIndex(of: lhs.status) ?? statusOrder.count
                let rhsRank = statusOrder.firstIndex(of: rhs.status) ?? statusOrder.count
                return lhsRank == rhsRank ? lhs.position < rhs.position : lhsRank < rhsRank
            }
        return ProjectExportDocument(
            formatVersion: ProjectExportDocument.currentFormatVersion,
            project: .init(name: project.name, path: ProjectPathService.abbreviated(project.path)),
            tasks: ordered.map { .init(title: $0.title, prompt: $0.prompt, status: $0.status, position: $0.position) }
        )
    }

    static func encode(_ document: ProjectExportDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    static func decode(_ data: Data) throws -> ProjectExportDocument {
        let decoder = JSONDecoder()
        let probe: VersionProbe
        do {
            probe = try decoder.decode(VersionProbe.self, from: data)
        } catch let error as DecodingError {
            throw ProjectExportError.malformed(describe(error))
        }
        guard probe.formatVersion == ProjectExportDocument.currentFormatVersion else {
            throw ProjectExportError.unsupportedFormatVersion(probe.formatVersion)
        }

        let document: ProjectExportDocument
        do {
            document = try decoder.decode(ProjectExportDocument.self, from: data)
        } catch let error as DecodingError {
            throw ProjectExportError.malformed(describe(error))
        }

        guard !document.project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectExportError.emptyProjectName
        }
        _ = try expandedPath(document.project.path)
        return document
    }

    /// Accepts `~`, `~/...` and absolute paths. Relative paths have no stable base across
    /// machines, so they are rejected.
    static func expandedPath(_ string: String) throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let absolute: String
        if string == homePrefix {
            absolute = home
        } else if string.hasPrefix(homePrefix + pathSeparator) {
            absolute = home + string.dropFirst(homePrefix.count)
        } else if string.hasPrefix(pathSeparator) {
            absolute = string
        } else {
            throw ProjectExportError.malformed("project path \"\(string)\" must be absolute or start with ~/")
        }
        // Rebuilt from a plain path string so results compare equal to other file URLs.
        return URL(fileURLWithPath: (absolute as NSString).standardizingPath)
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            "missing \"\(keyPath(context.codingPath + [key]))\""
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            "unexpected value at \"\(keyPath(context.codingPath))\""
        case .dataCorrupted(let context):
            context.codingPath.isEmpty ? "not valid JSON" : "invalid value at \"\(keyPath(context.codingPath))\""
        @unknown default:
            "unreadable content"
        }
    }

    private static func keyPath(_ codingPath: [any CodingKey]) -> String {
        codingPath
            .map { key in key.intValue.map { "[\($0)]" } ?? key.stringValue }
            .joined(separator: ".")
    }
}
