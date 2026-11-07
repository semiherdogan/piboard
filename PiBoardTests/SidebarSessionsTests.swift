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

    @Test func outlineListsSessionsAndMoreUnderOpenProjectsOnly() {
        let open = UUID()
        let folded = UUID()
        let empty = UUID()
        let session = makeTask(status: .inProgress, position: 0)
        let listings = [
            open: SidebarSessions.Listing(visible: [session], hiddenCount: 2),
            folded: SidebarSessions.Listing(visible: [makeTask(status: .inProgress, position: 0)], hiddenCount: 0),
            empty: SidebarSessions.Listing(visible: [], hiddenCount: 0),
        ]

        let rows = SidebarOutline.rows(projectIDs: [open, folded, empty], listings: listings, collapsed: [folded])

        #expect(rows == [.project(open), .session(session.id), .more(projectID: open, count: 2), .project(folded), .project(empty)])
    }

    @Test func droppingAProjectAmongAnotherProjectsSessionsPutsItAfterThatProject() {
        let (a, b, c) = (UUID(), UUID(), UUID())
        let rows: [SidebarOutline.Row] = [.project(a), .session(UUID()), .session(UUID()), .project(b), .project(c)]

        // c dropped between a's two sessions lands after a's group, before b.
        #expect(SidebarOutline.projectOrder(movingRowAt: 4, to: 2, in: rows, projectIDs: [a, b, c]) == [a, c, b])
        // a dropped at the very end.
        #expect(SidebarOutline.projectOrder(movingRowAt: 0, to: rows.count, in: rows, projectIDs: [a, b, c]) == [b, c, a])
        // b dropped on top.
        #expect(SidebarOutline.projectOrder(movingRowAt: 3, to: 0, in: rows, projectIDs: [a, b, c]) == [b, a, c])
    }

    @Test func aMoveThatChangesNothingOrStartsOnASessionIsIgnored() {
        let (a, b) = (UUID(), UUID())
        let rows: [SidebarOutline.Row] = [.project(a), .session(UUID()), .project(b)]

        #expect(SidebarOutline.projectOrder(movingRowAt: 0, to: 1, in: rows, projectIDs: [a, b]) == nil)
        #expect(SidebarOutline.projectOrder(movingRowAt: 1, to: 0, in: rows, projectIDs: [a, b]) == nil)
    }

    @Test func moveUpAndDownSwapNeighboursAndStopAtTheEnds() {
        let (a, b, c) = (UUID(), UUID(), UUID())

        #expect(SidebarOutline.projectOrder(moving: b, by: -1, in: [a, b, c]) == [b, a, c])
        #expect(SidebarOutline.projectOrder(moving: b, by: 1, in: [a, b, c]) == [a, c, b])
        #expect(SidebarOutline.projectOrder(moving: a, by: -1, in: [a, b, c]) == nil)
        #expect(SidebarOutline.projectOrder(moving: c, by: 1, in: [a, b, c]) == nil)
    }

    private func makeResolver() -> ProjectClickResolver {
        ProjectClickResolver(navigationWindow: 0.1)
    }

    // The order seen in the app: the tap lands just before the selection change.
    @Test func aDoubleClickFromATerminalFoldsOnItsSecondClick() {
        var resolver = makeResolver()
        let start = Date()

        let firstFolds = resolver.tapped(projectID: projectID, boardShown: false, at: start)
        resolver.selectionChanged(to: projectID, boardWasShown: false, at: start.addingTimeInterval(0.003))
        let secondFolds = resolver.tapped(projectID: projectID, boardShown: true, at: start.addingTimeInterval(0.26))

        #expect(firstFolds == false)
        #expect(secondFolds)
    }

    @Test func aVeryFastDoubleClickStillFoldsOnItsSecondClick() {
        var resolver = makeResolver()
        let start = Date()

        _ = resolver.tapped(projectID: projectID, boardShown: false, at: start)
        resolver.selectionChanged(to: projectID, boardWasShown: false, at: start.addingTimeInterval(0.003))
        let secondFolds = resolver.tapped(projectID: projectID, boardShown: true, at: start.addingTimeInterval(0.05))

        #expect(secondFolds)
    }

    @Test func whenTheSelectionChangeComesFirstItsOwnTapDoesNotFold() {
        var resolver = makeResolver()
        let start = Date()

        resolver.selectionChanged(to: projectID, boardWasShown: false, at: start)
        let folds = resolver.tapped(projectID: projectID, boardShown: true, at: start.addingTimeInterval(0.003))

        #expect(folds == false)
    }

    @Test func aClickWhileTheBoardIsShownFolds() {
        var resolver = makeResolver()
        let start = Date()

        resolver.selectionChanged(to: projectID, boardWasShown: true, at: start)

        let folds = resolver.tapped(projectID: projectID, boardShown: true, at: start.addingTimeInterval(0.1))
        #expect(folds)
    }

    @Test func aStaleNavigationFromTheKeyboardDoesNotSwallowALaterClick() {
        var resolver = makeResolver()
        let start = Date()
        resolver.selectionChanged(to: projectID, boardWasShown: false, at: start)

        let folds = resolver.tapped(projectID: projectID, boardShown: true, at: start.addingTimeInterval(5))
        #expect(folds)
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
