import Foundation

// Named BoardTask to avoid clashing with Swift's own `Task`.
struct BoardTask: Identifiable, Equatable, Sendable {
    let id: UUID
    var projectId: UUID
    var title: String
    var prompt: String
    var status: TaskStatus
    var position: Int
    var piSessionId: UUID?
    var runContext: RunContext?
    var worktreePath: URL?
    var worktreeBranch: String?
    var createdAt: Date
    var updatedAt: Date
}
