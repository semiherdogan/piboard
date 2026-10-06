enum RunContext: String, Codable, Sendable {
    case current
    case worktree

    var title: String {
        switch self {
        case .current: "Current Working Tree"
        case .worktree: "New Worktree"
        }
    }
}
