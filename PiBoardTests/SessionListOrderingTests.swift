import Foundation
import Testing
@testable import PiBoard

struct SessionListOrderingTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func makeTask(title: String, updated: TimeInterval, created: TimeInterval = 0) -> BoardTask {
        BoardTask(
            id: UUID(),
            projectId: UUID(),
            agent: .default,
            title: title,
            prompt: "",
            status: .backlog,
            position: 0,
            sessionID: nil,
            runContext: nil,
            worktreePath: nil,
            worktreeBranch: nil,
            createdAt: base.addingTimeInterval(created),
            updatedAt: base.addingTimeInterval(updated)
        )
    }

    @Test func liveSessionsComeFirstThenNewestUpdateFirst() {
        let oldLive = makeTask(title: "old live", updated: 1)
        let newIdle = makeTask(title: "new idle", updated: 30)
        let midIdle = makeTask(title: "mid idle", updated: 20)
        let newLive = makeTask(title: "new live", updated: 10)

        let sorted = SessionListOrdering.sorted([oldLive, newIdle, midIdle, newLive]) { $0 == oldLive.id || $0 == newLive.id }

        #expect(sorted.map(\.title) == ["new live", "old live", "new idle", "mid idle"])
    }

    @Test func equalUpdateTimesFallBackToNewestCreated() {
        let older = makeTask(title: "older", updated: 5, created: 1)
        let newer = makeTask(title: "newer", updated: 5, created: 2)

        let sorted = SessionListOrdering.sorted([older, newer]) { _ in false }

        #expect(sorted.map(\.title) == ["newer", "older"])
    }

    @Test func emptyInputStaysEmpty() {
        #expect(SessionListOrdering.sorted([]) { _ in true }.isEmpty)
    }
}
