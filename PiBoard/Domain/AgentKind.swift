import Foundation

/// The coding agent a task runs. Raw values are stored in SQLite and in export files; never rename one.
enum AgentKind: String, CaseIterable, Codable, Sendable {
    case pi
    case opencode

    static let `default` = AgentKind.pi

    /// Product name as shown in buttons and badges ("Stop Pi", "Pi exited").
    var title: String {
        switch self {
        case .pi: "Pi"
        case .opencode: "OpenCode"
        }
    }

    /// Badge label; separate from `title` so a long product name can shorten here.
    var shortTitle: String {
        switch self {
        case .pi: "Pi"
        case .opencode: "OpenCode"
        }
    }

    var systemImage: String {
        switch self {
        case .pi: "circle.hexagongrid"
        case .opencode: "chevron.left.forwardslash.chevron.right"
        }
    }
}
