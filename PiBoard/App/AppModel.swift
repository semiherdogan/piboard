import Foundation
import Observation

@MainActor
@Observable
final class BoardModel {
    var projects: [Project]
    var tasks: [BoardTask]
    var runtimeStates: [UUID: TaskRuntimeState]
    var selectedProjectID: UUID?
    var selectedTaskID: UUID?
    // Set after a Backlog -> In Progress move; the preparation sheet that consumes this lands
    // in M0 step 6 part 2.
    var pendingPreparationTaskID: UUID?

    init(sample: Bool) {
        if sample {
            projects = SampleData.projects
            tasks = SampleData.tasks
            runtimeStates = SampleData.runtimeStates
            selectedProjectID = SampleData.projects.first?.id
        } else {
            projects = []
            tasks = []
            runtimeStates = [:]
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
        runtimeStates.removeValue(forKey: taskID)
        if selectedTaskID == taskID {
            selectedTaskID = nil
        }
    }

    func updateProjectPath(_ projectID: UUID, path: URL) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].path = path
        projects[index].updatedAt = Date()
    }
}
