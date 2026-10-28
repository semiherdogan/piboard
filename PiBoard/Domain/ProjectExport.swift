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
        var defaultAgent: AgentKind

        enum CodingKeys: String, CodingKey {
            case name, path, defaultAgent
        }
    }

    struct TaskPayload: Codable, Equatable, Sendable {
        var title: String
        var prompt: String
        var status: TaskStatus
        var position: Int
        var agent: AgentKind

        enum CodingKeys: String, CodingKey {
            case title, prompt, status, position, agent
        }
    }

    var formatVersion: Int
    var project: ProjectPayload
    var tasks: [TaskPayload]

    static func defaultFileName(for projectName: String) -> String {
        "\(projectName).\(fileExtension)"
    }
}

extension ProjectExportDocument.ProjectPayload {
    // Files written before agents existed have no key; they default to Pi.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        let rawAgent = try container.decodeIfPresent(String.self, forKey: .defaultAgent)
        defaultAgent = try ProjectExportDocument.agent(from: rawAgent)
    }
}

extension ProjectExportDocument {
    static func agent(from rawValue: String?) throws -> AgentKind {
        guard let rawValue else { return .default }
        guard let agent = AgentKind(rawValue: rawValue) else {
            throw ProjectExportError.invalidAgent(rawValue)
        }
        return agent
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
        agent = try ProjectExportDocument.agent(from: container.decodeIfPresent(String.self, forKey: .agent))
    }
}

enum ProjectExportError: LocalizedError, Equatable {
    case unsupportedFormatVersion(Int)
    case malformed(String)
    case emptyProjectName
    case invalidStatus(String)
    case invalidAgent(String)

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
        case .invalidAgent(let agent):
            "The file contains an unknown agent \"\(agent)\"."
        }
    }
}
