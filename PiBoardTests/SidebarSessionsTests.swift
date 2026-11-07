import Foundation
import Testing
@testable import PiBoard

struct SidebarSessionsTests {
    private let projectID = UUID()

    private func makeTask(status: TaskStatus, position: Int, sessionID: String? = "session") -> BoardTask {
        BoardTask(
            id: UUID(),
            projectId: projectID,
            agent: .default,
            title: "Task",
            prompt: "",
            status: status,
            position: position,
            sessionID: sessionID,
            runContext: nil,
            worktreePath: nil,
            worktreeBranch: nil,
            createdAt: .now,
            updatedAt: .now
        )
    }

    @Test func listsOnlyInProgressTasksWithASessionInBoardOrder() {
        let second = makeTask(status: .inProgress, position: 1)
        let first = makeTask(status: .inProgress, position: 0)
        let tasks = [
            second,
            makeTask(status: .inProgress, position: 2, sessionID: nil),
            makeTask(status: .backlog, position: 0),
            makeTask(status: .done, position: 0),
            first,
        ]

        let listing = SidebarSessions.listing(for: tasks, hasLiveSession: { _ in false })

        #expect(listing.visible.map(\.id) == [first.id, second.id])
        #expect(listing.hiddenCount == 0)
    }

    @Test func aLiveSessionWithoutAStoredIDIsListed() {
        let task = makeTask(status: .inProgress, position: 0, sessionID: nil)

        let listing = SidebarSessions.listing(for: [task], hasLiveSession: { $0 == task.id })

        #expect(listing.visible.map(\.id) == [task.id])
    }

    @Test func rowsBeyondTheLimitAreCountedNotListed() {
        let limit = 2
        let tasks = (0..<5).map { makeTask(status: .inProgress, position: $0) }

        let listing = SidebarSessions.listing(for: tasks, hasLiveSession: { _ in false }, limit: limit)

        #expect(listing.visible.map(\.id) == tasks.prefix(limit).map(\.id))
        #expect(listing.hiddenCount == 3)
    }

    @Test(arguments: [
        (0.0, "now"),
        (59.0, "now"),
        (60.0, "1m"),
        (3_599.0, "59m"),
        (3_600.0, "1h"),
        (86_399.0, "23h"),
        (86_400.0, "1d"),
        (-30.0, "now"),
    ])
    func compactElapsedTime(seconds: Double, expected: String) {
        let now = Date()
        #expect(CompactElapsedTime.string(from: now.addingTimeInterval(-seconds), to: now) == expected)
    }
}
