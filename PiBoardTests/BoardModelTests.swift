import Foundation
import Testing
@testable import PiBoard

@MainActor
struct BoardModelTests {
    private func makeSeededModel() throws -> BoardModel {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)
        let model = BoardModel(database: database)
        SampleData.seed(into: model)
        return model
    }

    @Test func tasksForStatusReturnsSortedPositions() throws {
        let model = try makeSeededModel()
        guard let project = model.projects.first else {
            Issue.record("expected at least one sample project")
            return
        }
        let backlog = model.tasks(for: project.id, status: .backlog)
        #expect(backlog == backlog.sorted { $0.position < $1.position })
    }

    @Test func addTaskAppendsAtEndOfBacklog() throws {
        let model = try makeSeededModel()
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

    @Test func movingBacklogToInProgressSetsPendingPreparation() throws {
        let model = try makeSeededModel()
        guard let project = model.projects.first,
              let task = model.tasks(for: project.id, status: .backlog).first else {
            Issue.record("expected a backlog task in the sample data")
            return
        }

        // Seeding itself moves a couple of tasks to In Progress, so reset the flag the
        // move below is actually asserting on.
        model.pendingPreparationTaskID = nil
        model.move(taskID: task.id, to: .inProgress, at: 0)
        #expect(model.pendingPreparationTaskID == task.id)
    }

    @Test func inspectorIsNotPresentedByDefault() throws {
        let model = try makeSeededModel()
        #expect(model.isInspectorPresented == false)
    }

    @Test func terminalToOpenAfterPreparationDefaultsToNil() throws {
        let model = try makeSeededModel()
        #expect(model.terminalToOpenAfterPreparation == nil)
    }

    @Test func draggingTaskIDIsNilByDefault() throws {
        let model = try makeSeededModel()
        #expect(model.draggingTaskID == nil)
    }

    @Test func deleteTaskRemovesItAndClearsSelectionAndInspectorWhenSelected() throws {
        let model = try makeSeededModel()
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

    @Test func deleteProjectCascadesTasksAndMovesSelectionToAnotherProject() throws {
        let model = try makeSeededModel()
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

    @Test func requestMoveOnRunningTaskSetsPendingMoveConfirmationAndDoesNotMove() throws {
        let model = try makeSeededModel()
        guard let project = model.projects.first,
              let task = model.tasks(for: project.id, status: .inProgress).first else {
            Issue.record("expected an in-progress task in the sample data")
            return
        }

        model.requestMove(taskID: task.id, to: .done, at: 0, isRunning: { _ in true })

        #expect(model.pendingMoveConfirmation?.taskID == task.id)
        #expect(model.pendingMoveConfirmation?.targetStatus == .done)
        #expect(model.tasks.first { $0.id == task.id }?.status == .inProgress)
    }

    @Test func requestMoveOnNonRunningTaskMovesImmediately() throws {
        let model = try makeSeededModel()
        guard let project = model.projects.first,
              let task = model.tasks(for: project.id, status: .inProgress).first else {
            Issue.record("expected an in-progress task in the sample data")
            return
        }

        model.requestMove(taskID: task.id, to: .done, at: 0, isRunning: { _ in false })

        #expect(model.pendingMoveConfirmation == nil)
        #expect(model.tasks.first { $0.id == task.id }?.status == .done)
    }

    @Test func deleteProjectOfLastProjectLeavesSelectedProjectIDNil() throws {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)
        let model = BoardModel(database: database)
        model.addProject(name: "Only Project", path: URL(fileURLWithPath: "/tmp/only"))
        guard let project = model.projects.first else {
            Issue.record("expected the just-added project")
            return
        }

        model.deleteProject(id: project.id)

        #expect(model.projects.isEmpty)
        #expect(model.selectedProjectID == nil)
    }

    @Test func moveSurvivesReloadFromTheSameDatabase() throws {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)
        let model = BoardModel(database: database)
        SampleData.seed(into: model)
        guard let project = model.projects.first,
              let task = model.tasks(for: project.id, status: .backlog).first else {
            Issue.record("expected a backlog task in the sample data")
            return
        }

        model.move(taskID: task.id, to: .done, at: 0)

        let reloaded = BoardModel(database: database)
        #expect(reloaded.tasks.first { $0.id == task.id }?.status == .done)
        #expect(reloaded.tasks.first { $0.id == task.id }?.position == 0)
    }

    @Test func deleteProjectRemovesTasksFromAFreshModel() throws {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)
        let model = BoardModel(database: database)
        SampleData.seed(into: model)
        guard let projectToDelete = model.projects.first else {
            Issue.record("expected at least one sample project")
            return
        }

        model.deleteProject(id: projectToDelete.id)

        let reloaded = BoardModel(database: database)
        #expect(reloaded.projects.contains { $0.id == projectToDelete.id } == false)
        #expect(reloaded.tasks.contains { $0.projectId == projectToDelete.id } == false)
    }

    @Test func addProjectStoresCanonicalPath() throws {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)
        let model = BoardModel(database: database)

        model.addProject(name: "Canonical", path: URL(fileURLWithPath: "/private/tmp/../tmp/"))

        #expect(model.projects.first?.path.path == "/tmp")
    }

    @Test func updateProjectPersistsNameAndCanonicalPathAcrossReload() throws {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)
        let model = BoardModel(database: database)
        model.addProject(name: "Original", path: URL(fileURLWithPath: "/tmp"))
        guard let project = model.projects.first else {
            Issue.record("expected the just-added project")
            return
        }

        model.updateProject(id: project.id, name: "Renamed", path: URL(fileURLWithPath: "/private/tmp/../tmp/"))

        #expect(model.projects.first?.name == "Renamed")
        #expect(model.projects.first?.path.path == "/tmp")

        let reloaded = BoardModel(database: database)
        #expect(reloaded.projects.first?.name == "Renamed")
        #expect(reloaded.projects.first?.path.path == "/tmp")
    }

    @Test func selectedProjectIDRestoresFromSettingsOnReload() throws {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)
        let model = BoardModel(database: database)
        SampleData.seed(into: model)
        guard let targetProject = model.projects.last, model.projects.count > 1 else {
            Issue.record("expected more than one sample project")
            return
        }
        model.selectedProjectID = targetProject.id

        let reloaded = BoardModel(database: database)

        #expect(reloaded.selectedProjectID == targetProject.id)
    }
}
