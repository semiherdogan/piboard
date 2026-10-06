import Foundation

/// Portable project file. Holds only machine-independent fields; ids, timestamps, Pi
/// sessions, run contexts and worktrees stay on the machine that exported them.
struct ProjectExportDocument: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1
    static let fileExtension = "piboard.json"

    struct ProjectPayload: Codable, Equatable, Sendable {
        var name: String
        // Home directory abbreviated to `~` so the file stays valid for another user.
        var path: String
    }

    struct TaskPayload: Codable, Equatable, Sendable {
        var title: String
        var prompt: String
        var status: TaskStatus
        var position: Int

        enum CodingKeys: String, CodingKey {
            case title, prompt, status, position
        }
    }

    var formatVersion: Int
    var project: ProjectPayload
    var tasks: [TaskPayload]

    static func defaultFileName(for projectName: String) -> String {
        "\(projectName).\(fileExtension)"
    }
}

extension ProjectExportDocument.TaskPayload {
    // Decoded by hand so an unknown status surfaces as `invalidStatus` instead of a generic
    // decoding failure.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        prompt = try container.decode(String.self, forKey: .prompt)
        let rawStatus = try container.decode(String.self, forKey: .status)
        guard let status = TaskStatus(rawValue: rawStatus) else {
            throw ProjectExportError.invalidStatus(rawStatus)
        }
        self.status = status
        position = try container.decode(Int.self, forKey: .position)
    }
}

enum ProjectExportError: LocalizedError, Equatable {
    case unsupportedFormatVersion(Int)
    case malformed(String)
    case emptyProjectName
    case invalidStatus(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormatVersion(let version):
            "This file uses format version \(version), but PiBoard only supports version \(ProjectExportDocument.currentFormatVersion)."
        case .malformed(let detail):
            "The file is not a valid PiBoard project: \(detail)"
        case .emptyProjectName:
            "The project name in the file is empty."
        case .invalidStatus(let status):
            "The file contains a task with unknown status \"\(status)\"."
        }
    }
}
