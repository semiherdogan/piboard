import SwiftUI

struct BoardColumnView: View {
    let project: Project
    let status: TaskStatus
    @Environment(AppEnvironment.self) private var environment

    private var tasks: [BoardTask] {
        environment.board.tasks(for: project.id, status: status)
    }

    private var emptyStateText: String {
        switch status {
        case .backlog: "Nothing in Backlog"
        case .inProgress: "Drag a task here to start it"
        case .done: "Nothing finished yet"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            ScrollView(.vertical) {
                LazyVStack(spacing: 8) {
                    ForEach(tasks) { task in
                        TaskCardView(task: task)
                            .dropDestination(for: TaskDragItem.self) { items, _ in
                                drop(items, before: task)
                            }
                    }

                    if tasks.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .top)
                .dropDestination(for: TaskDragItem.self) { items, _ in
                    drop(items, before: nil)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(status.title)
                .font(.headline)
            Text("\(tasks.count)")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.title3)
            Text(emptyStateText)
                .font(.callout)
        }
        .foregroundStyle(.tertiary)
    }

    private func drop(_ items: [TaskDragItem], before targetTask: BoardTask?) -> Bool {
        guard let item = items.first else { return false }
        let columnTasks = tasks
        let index: Int
        if let targetTask, let targetIndex = columnTasks.firstIndex(where: { $0.id == targetTask.id }) {
            index = targetIndex
        } else {
            index = columnTasks.count
        }
        withAnimation(.snappy) {
            environment.board.move(taskID: item.taskID, to: status, at: index)
        }
        return true
    }
}
