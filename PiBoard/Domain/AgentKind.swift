import Foundation

/// The coding agent a task runs. Raw values are stored in SQLite and in export files; never rename one.
enum AgentKind: String, CaseIterable, Codable, Sendable {
    case pi

    static let `default` = AgentKind.pi

    /// Product name as shown in buttons and badges ("Stop Pi", "Pi exited").
    var title: String {
        switch self {
        case .pi: "Pi"
        }
    }
}
