import Testing
@testable import PiBoard

@MainActor
struct BoardModelTests {
    @Test func tasksForStatusReturnsSortedPositions() {
        let model = BoardModel(sample: true)
        guard let project = model.projects.first else {
            Issue.record("expected at least one sample project")
            return
        }
        let backlog = model.tasks(for: project.id, status: .backlog)
        #expect(backlog == backlog.sorted { $0.position < $1.position })
    }

    @Test func addTaskAppendsAtEndOfBacklog() {
        let model = BoardModel(sample: true)
        guard let project = model.projects.first else {
            Issue.record("expected at least one sample project")
            return
        }
        let countBefore = model.tasks(for: project.id, status: .backlog).count

        model.addTask(title: "New task", prompt: "Do the thing", to: project.id)

        let backlog = model.tasks(for: project.id, status: .backlog)
        #expect(backlog.count == countBefore + 1)
        #expect(backlog.last?.title == "New task")
        #expect(backlog.last?.position == countBefore)
    }

    @Test func movingBacklogToInProgressSetsPendingPreparation() {
        let model = BoardModel(sample: true)
        guard let project = model.projects.first,
              let task = model.tasks(for: project.id, status: .backlog).first else {
            Issue.record("expected a backlog task in the sample data")
            return
        }

        #expect(model.pendingPreparationTaskID == nil)
        model.move(taskID: task.id, to: .inProgress, at: 0)
        #expect(model.pendingPreparationTaskID == task.id)
    }
}
