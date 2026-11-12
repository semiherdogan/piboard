import Foundation

enum SessionListOrdering {
    /// Live sessions first, then the most recently updated; ties fall back to creation time and id so the order never flickers.
    static func sorted(_ tasks: [BoardTask], isLive: (UUID) -> Bool) -> [BoardTask] {
        let live = Set(tasks.filter { isLive($0.id) }.map(\.id))
        return tasks.sorted { lhs, rhs in
            let lhsLive = live.contains(lhs.id)
            let rhsLive = live.contains(rhs.id)
            if lhsLive != rhsLive { return lhsLive }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
