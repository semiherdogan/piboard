import Foundation

struct Project: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var path: URL
    var createdAt: Date
    var updatedAt: Date
}
