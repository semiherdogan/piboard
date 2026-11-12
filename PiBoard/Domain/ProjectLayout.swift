enum ProjectLayout: String, CaseIterable, Sendable {
    case board
    case list

    static let `default` = ProjectLayout.board

    var title: String {
        switch self {
        case .board: "Board"
        case .list: "List"
        }
    }

    var systemImage: String {
        switch self {
        case .board: "rectangle.split.3x1"
        case .list: "list.bullet"
        }
    }
}
