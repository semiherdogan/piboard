import Foundation

/// How a task's agent session is shown: the agent's own terminal UI or PiBoard's native chat.
enum SessionInterface: String, CaseIterable, Sendable {
    case terminal
    case chat

    static let `default` = SessionInterface.terminal

    var title: String {
        switch self {
        case .terminal: "Terminal"
        case .chat: "Chat"
        }
    }

    var systemImage: String {
        switch self {
        case .terminal: "terminal"
        case .chat: "bubble.left.and.bubble.right"
        }
    }
}
