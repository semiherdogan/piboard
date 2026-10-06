import Foundation
import Testing
@testable import PiBoard

struct TaskOrderingTests {
    private func makeTask(id: UUID = UUID(), projectId: UUID, status: TaskStatus, position: Int) -> BoardTask {
        BoardTask(
            id: id,
            projectId: projectId,
            title: "Task",
            prompt: "",
            status: status,
            position: position,
            piSessionId: nil,
            runContext: nil,
            worktreePath: nil,
            worktreeBranch: nil,
            createdAt: .now,
            updatedAt: .now
        )
    }

    @Test func moveWithinColumnDownRenormalizes() {
        let projectID = UUID()
        let a = makeTask(projectId: projectID, status: .backlog, position: 0)
        let b = makeTask(projectId: projectID, status: .backlog, position: 1)
        let c = makeTask(projectId: projectID, status: .backlog, position: 2)
        let result = TaskOrdering.reorder(tasks: [a, b, c], taskID: a.id, to: .backlog, at: 2)

        let byID = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
        #expect(byID[b.id]?.position == 0)
        #expect(byID[c.id]?.position == 1)
        #expect(byID[a.id]?.position == 2)
    }

    @Test func moveWithinColumnUpRenormalizes() {
        let projectID = UUID()
        let a = makeTask(projectId: projectID, status: .backlog, position: 0)
        let b = makeTask(projectId: projectID, status: .backlog, position: 1)
        let c = makeTask(projectId: projectID, status: .backlog, position: 2)
        let result = TaskOrdering.reorder(tasks: [a, b, c], taskID: c.id, to: .backlog, at: 0)

        let byID = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
        #expect(byID[c.id]?.position == 0)
        #expect(byID[a.id]?.position == 1)
        #expect(byID[b.id]?.position == 2)
    }

    @Test func moveAcrossColumnsRenormalizesBothColumns() {
        let projectID = UUID()
        let a = makeTask(projectId: projectID, status: .backlog, position: 0)
        let b = makeTask(projectId: projectID, status: .backlog, position: 1)
        let x = makeTask(projectId: projectID, status: .inProgress, position: 0)
        let result = TaskOrdering.reorder(tasks: [a, b, x], taskID: a.id, to: .inProgress, at: 0)

        let byID = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
        #expect(byID[a.id]?.status == .inProgress)
        #expect(byID[a.id]?.position == 0)
        #expect(byID[x.id]?.status == .inProgress)
        #expect(byID[x.id]?.position == 1)
        #expect(byID[b.id]?.status == .backlog)
        #expect(byID[b.id]?.position == 0)
    }

    @Test func moveToEndWhenIndexExceedsCount() {
        let projectID = UUID()
        let a = makeTask(projectId: projectID, status: .backlog, position: 0)
        let x = makeTask(projectId: projectID, status: .inProgress, position: 0)
        let result = TaskOrdering.reorder(tasks: [a, x], taskID: a.id, to: .inProgress, at: 99)

        let byID = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
        #expect(byID[a.id]?.position == 1)
        #expect(byID[x.id]?.position == 0)
    }

    @Test func movingTaskOntoItselfIsNoOp() {
        let projectID = UUID()
        let a = makeTask(projectId: projectID, status: .backlog, position: 0)
        let b = makeTask(projectId: projectID, status: .backlog, position: 1)
        let result = TaskOrdering.reorder(tasks: [a, b], taskID: a.id, to: .backlog, at: 0)

        let byID = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
        #expect(byID[a.id]?.position == 0)
        #expect(byID[b.id]?.position == 1)
    }

    @Test func movingTaskInOneProjectLeavesOtherProjectsUntouched() {
        let projectA = UUID()
        let projectB = UUID()
        let a0 = makeTask(projectId: projectA, status: .backlog, position: 0)
        let a1 = makeTask(projectId: projectA, status: .backlog, position: 1)
        let a2 = makeTask(projectId: projectA, status: .backlog, position: 2)
        let b0 = makeTask(projectId: projectB, status: .backlog, position: 0)
        let b1 = makeTask(projectId: projectB, status: .backlog, position: 1)

        let result = TaskOrdering.reorder(
            tasks: [a0, a1, a2, b0, b1],
            taskID: a0.id,
            to: .backlog,
            at: 2
        )

        let byID = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
        #expect(byID[b0.id] == b0)
        #expect(byID[b1.id] == b1)
        #expect(byID[a1.id]?.position == 0)
        #expect(byID[a2.id]?.position == 1)
        #expect(byID[a0.id]?.position == 2)
    }

    @Test func moveWithinColumnDownUsesIndexAfterDraggedTaskIsExcluded() {
        // Five tasks at positions 0..4; dragging index 1 "before the card currently at
        // index 4" means the caller passes index 3 once the dragged task is excluded
        // from the comparison, since removing it shifts everything after it back by one.
        let projectID = UUID()
        let tasks = (0..<5).map { makeTask(projectId: projectID, status: .backlog, position: $0) }
        let result = TaskOrdering.reorder(tasks: tasks, taskID: tasks[1].id, to: .backlog, at: 3)

        let byID = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
        #expect(byID[tasks[0].id]?.position == 0)
        #expect(byID[tasks[2].id]?.position == 1)
        #expect(byID[tasks[3].id]?.position == 2)
        #expect(byID[tasks[1].id]?.position == 3)
        #expect(byID[tasks[4].id]?.position == 4)
    }

    @Test func reorderingTwoHundredTasksCompletesWellUnderOneHundredMilliseconds() {
        let projectID = UUID()
        let tasks = (0..<200).map { makeTask(projectId: projectID, status: .backlog, position: $0) }

        let start = DispatchTime.now()
        _ = TaskOrdering.reorder(tasks: tasks, taskID: tasks[50].id, to: .backlog, at: 150)
        let elapsedMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000

        #expect(elapsedMilliseconds < 100)
    }
}
