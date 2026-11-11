import Foundation

struct Project: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var path: URL
    var defaultAgent: AgentKind
    var trustsPiResources = false
    var createdAt: Date
    var updatedAt: Date
}
