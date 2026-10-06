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
    var selectedProjectID: UUID? {
        didSet {
            guard selectedProjectID != oldValue else { return }
            persistSelectedProjectID()
        }
    }
    var selectedTaskID: UUID?
    var isInspectorPresented = false {
        didSet {
            guard isInspectorPresented != oldValue else { return }
            Diagnostics.ui.info("inspector \(self.isInspectorPresented ? "presented" : "dismissed", privacy: .public)")
        }
    }
    var taskPendingDeletion: BoardTask?
    var projectPendingDeletion: Project?
    // Set after a Backlog -> In Progress move; consumed by TaskPreparationView.
    var pendingPreparationTaskID: UUID? {
        didSet {
            guard pendingPreparationTaskID != oldValue else { return }
            if let pendingPreparationTaskID {
                Diagnostics.ui.info("preparation sheet present task=\(pendingPreparationTaskID.uuidString, privacy: .public)")
            } else {
                Diagnostics.ui.info("preparation sheet dismiss")
            }
        }
    }
    // Set by TaskPreparationView on success, before dismiss; moved into openTerminalTaskID
    // by the sheet's onDismiss so the detail swap happens after the sheet is gone.
    var terminalToOpenAfterPreparation: UUID?
    // Set when the terminal workspace should replace the board in the detail column.
    var openTerminalTaskID: UUID?
    var pendingMoveConfirmation: PendingMoveConfirmation?
    // Non-blocking banner for a failed write-through to the database.
    var lastError: String?

    private let projectRepository: ProjectRepository
    private let taskRepository: TaskRepository
    private let settingsRepository: SettingsRepository

    init(database: Database) {
        let projectRepository = ProjectRepository(database: database)
        let taskRepository = TaskRepository(database: database)
        let settingsRepository = SettingsRepository(database: database)
        self.projectRepository = projectRepository
        self.taskRepository = taskRepository
        self.settingsRepository = settingsRepository

        let loadedProjects = (try? projectRepository.fetchAll()) ?? []
        var loadedTasks: [BoardTask] = []
        for project in loadedProjects {
            loadedTasks.append(contentsOf: (try? taskRepository.fetchAll(projectID: project.id)) ?? [])
        }
        projects = loadedProjects
        tasks = loadedTasks

        if let savedIDString = settingsRepository.get(.lastOpenedProjectID),
           let savedID = UUID(uuidString: savedIDString),
           loadedProjects.contains(where: { $0.id == savedID }) {
            selectedProjectID = savedID
        } else {
            selectedProjectID = loadedProjects.first?.id
        }
    }

    // Dismisses the inspector before the detail column swaps to the terminal so its
    // presenter is never torn down mid-presentation.
    func openTerminal(for taskID: UUID) {
        Diagnostics.ui.info("openTerminal task=\(taskID.uuidString, privacy: .public) inspectorWasPresented=\(self.isInspectorPresented, privacy: .public)")
        isInspectorPresented = false
        // Deferred so the triggering click finishes before the board leaves the hierarchy;
        // removing it mid-event can leave the hosting view tracking a gesture that never ends.
        Task { @MainActor in
            self.openTerminalTaskID = taskID
        }
    }

    func tasks(for project: UUID, status: TaskStatus) -> [BoardTask] {
        tasks
            .filter { $0.projectId == project && $0.status == status }
            .sorted { $0.position < $1.position }
    }

    func addTask(title: String, prompt: String, to project: UUID) {
        let position = (tasks(for: project, status: .backlog).map(\.position).max()).map { $0 + 1 } ?? 0
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
        do {
            try taskRepository.insert(task)
            tasks.append(task)
        } catch {
            lastError = "Could not save the new task: \(error)"
        }
    }

    func addProject(name: String, path: URL) {
        let now = Date()
        let project = Project(id: UUID(), name: name, path: ProjectPathService.canonicalize(path), createdAt: now, updatedAt: now)
        do {
            try projectRepository.insert(project)
            projects.append(project)
            selectedProjectID = project.id
        } catch {
            lastError = "Could not save the new project: \(error)"
        }
    }

    func move(taskID: BoardTask.ID, to status: TaskStatus, at index: Int) {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return }
        let wasBacklog = task.status == .backlog

        let snapshot = tasks
        var reordered = TaskOrdering.reorder(tasks: tasks, taskID: taskID, to: status, at: index)
        if let movedIndex = reordered.firstIndex(where: { $0.id == taskID }) {
            reordered[movedIndex].updatedAt = Date()
        }
        tasks = reordered

        do {
            try taskRepository.applyOrdering(reordered, movedTaskID: taskID)
        } catch {
            tasks = snapshot
            lastError = "Could not save the task move: \(error)"
            return
        }

        if wasBacklog && status == .inProgress {
            pendingPreparationTaskID = taskID
        }
    }

    func deleteTask(_ taskID: BoardTask.ID) {
        do {
            try taskRepository.delete(id: taskID)
            tasks.removeAll { $0.id == taskID }
            if selectedTaskID == taskID {
                selectedTaskID = nil
            }
        } catch {
            lastError = "Could not delete the task: \(error)"
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
        updateTask(taskID) { task in
            task.piSessionId = sessionID
        }
    }

    func setRunContext(_ runContext: RunContext, for taskID: BoardTask.ID) {
        updateTask(taskID) { task in
            task.runContext = runContext
        }
    }

    func setWorktree(path: URL, branch: String, for taskID: BoardTask.ID) {
        updateTask(taskID) { task in
            task.worktreePath = path
            task.worktreeBranch = branch
        }
    }

    func clearWorktree(for taskID: BoardTask.ID) {
        updateTask(taskID) { task in
            task.worktreePath = nil
            task.worktreeBranch = nil
            task.runContext = nil
        }
    }

    func updatePrompt(_ prompt: String, for taskID: BoardTask.ID) {
        updateTask(taskID) { task in
            task.prompt = prompt
        }
    }

    func updateTitle(_ title: String, for taskID: BoardTask.ID) {
        updateTask(taskID) { task in
            task.title = title
        }
    }

    func updateProject(id: UUID, name: String, path: URL) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        var updated = projects[index]
        updated.name = name
        updated.path = ProjectPathService.canonicalize(path)
        updated.updatedAt = Date()
        do {
            try projectRepository.update(updated)
            projects[index] = updated
        } catch {
            lastError = "Could not save the project: \(error)"
        }
    }

    func tasks(for projectID: UUID) -> [BoardTask] {
        tasks.filter { $0.projectId == projectID }
    }

    func deleteProject(id: UUID) {
        do {
            try projectRepository.delete(id: id)
        } catch {
            lastError = "Could not delete the project: \(error)"
            return
        }
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

    private func updateTask(_ taskID: BoardTask.ID, mutate: (inout BoardTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        var updated = tasks[index]
        mutate(&updated)
        updated.updatedAt = Date()
        do {
            try taskRepository.update(updated)
            tasks[index] = updated
        } catch {
            lastError = "Could not save the task: \(error)"
        }
    }

    private func persistSelectedProjectID() {
        guard let selectedProjectID else { return }
        do {
            try settingsRepository.set(.lastOpenedProjectID, value: selectedProjectID.uuidString.uppercased())
        } catch {
            lastError = "Could not save the selected project: \(error)"
        }
    }
}
