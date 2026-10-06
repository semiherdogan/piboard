import Foundation
import Testing
@testable import PiBoard

struct TaskOrderingTests {
    private func makeTask(id: UUID = UUID(), status: TaskStatus, position: Int) -> BoardTask {
        BoardTask(
            id: id,
            projectId: UUID(),
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
        let a = makeTask(status: .backlog, position: 0)
        let b = makeTask(status: .backlog, position: 1)
        let c = makeTask(status: .backlog, position: 2)
        let result = TaskOrdering.reorder(tasks: [a, b, c], taskID: a.id, to: .backlog, at: 2)

        let byID = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
        #expect(byID[b.id]?.position == 0)
        #expect(byID[c.id]?.position == 1)
        #expect(byID[a.id]?.position == 2)
    }

    @Test func moveWithinColumnUpRenormalizes() {
        let a = makeTask(status: .backlog, position: 0)
        let b = makeTask(status: .backlog, position: 1)
        let c = makeTask(status: .backlog, position: 2)
        let result = TaskOrdering.reorder(tasks: [a, b, c], taskID: c.id, to: .backlog, at: 0)

        let byID = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
        #expect(byID[c.id]?.position == 0)
        #expect(byID[a.id]?.position == 1)
        #expect(byID[b.id]?.position == 2)
    }

    @Test func moveAcrossColumnsRenormalizesBothColumns() {
        let a = makeTask(status: .backlog, position: 0)
        let b = makeTask(status: .backlog, position: 1)
        let x = makeTask(status: .inProgress, position: 0)
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
        let a = makeTask(status: .backlog, position: 0)
        let x = makeTask(status: .inProgress, position: 0)
        let result = TaskOrdering.reorder(tasks: [a, x], taskID: a.id, to: .inProgress, at: 99)

        let byID = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
        #expect(byID[a.id]?.position == 1)
        #expect(byID[x.id]?.position == 0)
    }

    @Test func movingTaskOntoItselfIsNoOp() {
        let a = makeTask(status: .backlog, position: 0)
        let b = makeTask(status: .backlog, position: 1)
        let result = TaskOrdering.reorder(tasks: [a, b], taskID: a.id, to: .backlog, at: 0)

        let byID = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
        #expect(byID[a.id]?.position == 0)
        #expect(byID[b.id]?.position == 1)
    }
}
