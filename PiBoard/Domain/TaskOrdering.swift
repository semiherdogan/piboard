import Foundation

// Pure reordering logic, kept free of the model so it can later run inside a SQLite
// transaction unchanged.
enum TaskOrdering {
    /// Moves `taskID` to `status` at `index`, renormalizing positions 0..<N in both the
    /// source and target columns. Returns the updated task list; `tasks` order is not
    /// otherwise significant, only each task's `status`/`position` fields are read and written.
    static func reorder(
        tasks: [BoardTask],
        taskID: BoardTask.ID,
        to status: TaskStatus,
        at index: Int
    ) -> [BoardTask] {
        guard let movingIndex = tasks.firstIndex(where: { $0.id == taskID }) else {
            return tasks
        }

        var moving = tasks[movingIndex]
        let sourceStatus = moving.status
        let projectId = moving.projectId

        var byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })

        var targetColumn = tasks
            .filter { $0.status == status && $0.projectId == projectId && $0.id != taskID }
            .sorted { $0.position < $1.position }

        let clampedIndex = min(max(index, 0), targetColumn.count)
        moving.status = status
        targetColumn.insert(moving, at: clampedIndex)

        for (position, task) in targetColumn.enumerated() {
            var updated = task
            updated.position = position
            byID[updated.id] = updated
        }

        if sourceStatus != status {
            let sourceColumn = tasks
                .filter { $0.status == sourceStatus && $0.projectId == projectId && $0.id != taskID }
                .sorted { $0.position < $1.position }
            for (position, task) in sourceColumn.enumerated() {
                var updated = task
                updated.position = position
                byID[updated.id] = updated
            }
        }

        return tasks.map { byID[$0.id] ?? $0 }
    }
}
