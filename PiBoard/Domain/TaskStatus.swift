// Raw values match the SQLite CHECK constraint in the V1 schema.
enum TaskStatus: String, CaseIterable, Codable, Sendable {
    case backlog
    case inProgress = "in_progress"
    case done

    var title: String {
        switch self {
        case .backlog: "Backlog"
        case .inProgress: "In Progress"
        case .done: "Done"
        }
    }
}
