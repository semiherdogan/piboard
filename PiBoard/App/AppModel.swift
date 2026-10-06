import Foundation
import Observation

// Set when a task whose Pi process is running/starting is moved out of In Progress; the
// confirmation dialog is presented once from BoardView.
struct PendingMoveConfirmation: Equatable {
    let taskID: UUID
    let targetStatus: TaskStatus
    let targetIndex: Int
}

@MainActor
@Observable
final class BoardModel {
    var projects: [Project]
    var tasks: [BoardTask]
    var selectedProjectID: UUID?
    var selectedTaskID: UUID?
    var isInspectorPresented = false
    var taskPendingDeletion: BoardTask?
    var projectPendingDeletion: Project?
    // Set at drag start so drop validation and insertion-index math avoid waiting on the
    // Transferable's async XPC fetch.
    var draggingTaskID: UUID?
    // Set after a Backlog -> In Progress move; consumed by TaskPreparationView.
    var pendingPreparationTaskID: UUID?
    // Set when the terminal workspace should replace the board in the detail column.
    var openTerminalTaskID: UUID?
    var pendingMoveConfirmation: PendingMoveConfirmation?

    init(sample: Bool) {
        if sample {
            projects = SampleData.projects
            tasks = SampleData.tasks
            selectedProjectID = SampleData.projects.first?.id
        } else {
            projects = []
            tasks = []
            selectedProjectID = nil
        }
    }

    func tasks(for project: UUID, status: TaskStatus) -> [BoardTask] {
        tasks
            .filter { $0.projectId == project && $0.status == status }
            .sorted { $0.position < $1.position }
    }

    func addTask(title: String, prompt: String, to project: UUID) {
        let position = tasks(for: project, status: .backlog).count
        let now = Date()
        let task = BoardTask(
            id: UUID(),
            projectId: project,
            title: title,
            prompt: prompt,
            status: .backlog,
            position: position,
            piSessionId: nil,
            runContext: nil,
            worktreePath: nil,
            worktreeBranch: nil,
            createdAt: now,
            updatedAt: now
        )
        tasks.append(task)
    }

    func addProject(name: String, path: URL) {
        let now = Date()
        let project = Project(id: UUID(), name: name, path: path, createdAt: now, updatedAt: now)
        projects.append(project)
        selectedProjectID = project.id
    }

    func move(taskID: BoardTask.ID, to status: TaskStatus, at index: Int) {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return }
        let wasBacklog = task.status == .backlog
        tasks = TaskOrdering.reorder(tasks: tasks, taskID: taskID, to: status, at: index)
        if var updated = tasks.first(where: { $0.id == taskID }) {
            updated.updatedAt = Date()
            if let idx = tasks.firstIndex(where: { $0.id == taskID }) {
                tasks[idx] = updated
            }
        }
        if wasBacklog && status == .inProgress {
            pendingPreparationTaskID = taskID
        }
    }

    func deleteTask(_ taskID: BoardTask.ID) {
        tasks.removeAll { $0.id == taskID }
        if selectedTaskID == taskID {
            selectedTaskID = nil
        }
    }

    /// Moves immediately unless the task is running/starting and being moved out of In
    /// Progress, in which case the move is deferred until the caller confirms it.
    func requestMove(taskID: BoardTask.ID, to status: TaskStatus, at index: Int, isRunning: (UUID) -> Bool) {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return }
        if task.status == .inProgress, status != .inProgress, isRunning(taskID) {
            pendingMoveConfirmation = PendingMoveConfirmation(taskID: taskID, targetStatus: status, targetIndex: index)
            return
        }
        move(taskID: taskID, to: status, at: index)
    }

    func confirmPendingMove() {
        guard let pending = pendingMoveConfirmation else { return }
        pendingMoveConfirmation = nil
        move(taskID: pending.taskID, to: pending.targetStatus, at: pending.targetIndex)
    }

    func cancelPendingMove() {
        pendingMoveConfirmation = nil
    }

    func setPiSessionID(_ sessionID: UUID?, for taskID: BoardTask.ID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].piSessionId = sessionID
        tasks[index].updatedAt = Date()
    }

    func setRunContext(_ runContext: RunContext, for taskID: BoardTask.ID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].runContext = runContext
        tasks[index].updatedAt = Date()
    }

    func updatePrompt(_ prompt: String, for taskID: BoardTask.ID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].prompt = prompt
        tasks[index].updatedAt = Date()
    }

    func updateProjectPath(_ projectID: UUID, path: URL) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].path = path
        projects[index].updatedAt = Date()
    }

    func tasks(for projectID: UUID) -> [BoardTask] {
        tasks.filter { $0.projectId == projectID }
    }

    func deleteProject(id: UUID) {
        let taskIDsToDelete = tasks.filter { $0.projectId == id }.map(\.id)
        tasks.removeAll { $0.projectId == id }
        if selectedTaskID.map(taskIDsToDelete.contains) == true {
            selectedTaskID = nil
        }
        projects.removeAll { $0.id == id }
        if selectedProjectID == id {
            selectedProjectID = projects.first?.id
        }
    }
}
