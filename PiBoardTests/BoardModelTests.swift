import Foundation
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

    @Test func inspectorIsNotPresentedByDefault() {
        let model = BoardModel(sample: true)
        #expect(model.isInspectorPresented == false)
    }

    @Test func draggingTaskIDIsNilByDefault() {
        let model = BoardModel(sample: true)
        #expect(model.draggingTaskID == nil)
    }

    @Test func deleteTaskRemovesItAndClearsSelectionAndInspectorWhenSelected() {
        let model = BoardModel(sample: true)
        guard let project = model.projects.first,
              let task = model.tasks(for: project.id, status: .backlog).first else {
            Issue.record("expected a backlog task in the sample data")
            return
        }
        model.selectedTaskID = task.id
        model.isInspectorPresented = true

        model.deleteTask(task.id)

        #expect(model.tasks.contains { $0.id == task.id } == false)
        #expect(model.selectedTaskID == nil)
    }

    @Test func deleteProjectCascadesTasksAndMovesSelectionToAnotherProject() {
        let model = BoardModel(sample: true)
        #expect(model.projects.count > 1)
        guard let projectToDelete = model.projects.first else {
            Issue.record("expected at least one sample project")
            return
        }
        model.selectedProjectID = projectToDelete.id

        model.deleteProject(id: projectToDelete.id)

        #expect(model.projects.contains { $0.id == projectToDelete.id } == false)
        #expect(model.tasks.contains { $0.projectId == projectToDelete.id } == false)
        #expect(model.selectedProjectID == model.projects.first?.id)
        #expect(model.selectedProjectID != nil)
    }

    @Test func deleteProjectOfLastProjectLeavesSelectedProjectIDNil() {
        let model = BoardModel(sample: false)
        let project = Project(id: UUID(), name: "Only Project", path: URL(fileURLWithPath: "/tmp/only"), createdAt: Date(), updatedAt: Date())
        model.projects = [project]
        model.selectedProjectID = project.id

        model.deleteProject(id: project.id)

        #expect(model.projects.isEmpty)
        #expect(model.selectedProjectID == nil)
    }
}
