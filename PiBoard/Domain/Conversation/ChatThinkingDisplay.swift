import Foundation

/// How the chat view shows the model's thinking blocks.
enum ChatThinkingDisplay: String, CaseIterable, Sendable {
    case hidden
    case collapsed
    case expanded

    static let `default` = ChatThinkingDisplay.collapsed

    var title: String {
        switch self {
        case .hidden: "Hidden"
        case .collapsed: "Collapsed"
        case .expanded: "Expanded"
        }
    }
}

enum ChatShowsToolDetails {
    static let defaultValue = false
}
