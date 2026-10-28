import Foundation

struct Project: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var path: URL
    var defaultAgent: AgentKind
    var createdAt: Date
    var updatedAt: Date
}
