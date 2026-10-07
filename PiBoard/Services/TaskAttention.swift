import Foundation
import Observation

/// Tasks whose agent finished while the user was looking elsewhere.
///
/// The mark is what the dot on a task card and on its project row is drawn from. It is deliberately
/// not persisted: an agent that settled before the app was last quit is no longer news.
@MainActor
@Observable
final class TaskAttention {
    private(set) var taskIDs: Set<UUID> = []

    func mark(taskID: UUID) {
        taskIDs.insert(taskID)
    }

    func clear(taskID: UUID) {
        taskIDs.remove(taskID)
    }

    func has(taskID: UUID) -> Bool {
        taskIDs.contains(taskID)
    }

    /// True when any of the given tasks is marked; the project row has no task identity of its own.
    func hasAny(of candidates: some Sequence<UUID>) -> Bool {
        candidates.contains { taskIDs.contains($0) }
    }

    func clearAll() {
        taskIDs.removeAll()
    }
}
