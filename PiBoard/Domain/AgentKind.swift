import Foundation

/// The coding agent a task runs. Raw values are stored in SQLite and in export files; never rename one.
enum AgentKind: String, CaseIterable, Codable, Sendable {
    case pi
    /// PiG (Pi in Go), a native port that shares ~/.pi/agent with Pi, so sessions are interchangeable.
    case pig
    case opencode
    case claudeCode = "claude-code"

    static let `default` = AgentKind.pi

    /// Product name as shown in buttons and badges ("Stop Pi", "Pi exited").
    var title: String {
        switch self {
        case .pi: "Pi"
        case .pig: "PiG"
        case .opencode: "OpenCode"
        case .claudeCode: "Claude Code"
        }
    }

    /// Badge label; separate from `title` so a long product name can shorten here.
    var shortTitle: String {
        switch self {
        case .pi: "Pi"
        case .pig: "PiG"
        case .opencode: "OpenCode"
        case .claudeCode: "Claude"
        }
    }

    var systemImage: String {
        switch self {
        case .pi: "circle.hexagongrid"
        case .pig: "circle.hexagongrid.fill"
        case .opencode: "chevron.left.forwardslash.chevron.right"
        case .claudeCode: "asterisk"
        }
    }
}
