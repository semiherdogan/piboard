import SwiftUI

struct TaskCardView: View {
    let task: BoardTask
    @Environment(AppEnvironment.self) private var environment
    @State private var isHovered = false

    private var isSelected: Bool {
        environment.board.selectedTaskID == task.id
    }

    private var runtimeState: TaskRuntimeState {
        environment.board.runtimeStates[task.id] ?? .notStarted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title)
                .font(.body.weight(.medium))
                .lineLimit(2)

            if !task.prompt.isEmpty {
                Text(task.prompt)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            metadataRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .surfaceCard(isSelected: isSelected, isHovered: isHovered)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            environment.board.selectedTaskID = task.id
            environment.board.isInspectorPresented = true
        }
        .onTapGesture {
            environment.board.selectedTaskID = task.id
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .draggable(dragItem())
        .contextMenu {
            ForEach(TaskStatus.allCases.filter { $0 != task.status }, id: \.self) { status in
                Button("Move to \(status.title)") {
                    let targetCount = environment.board.tasks(for: task.projectId, status: status).count
                    environment.board.move(taskID: task.id, to: status, at: targetCount)
                }
            }
            Divider()
            Button("Delete Task", role: .destructive) {
                environment.board.taskPendingDeletion = task
            }
        }
    }

    private func dragItem() -> TaskDragItem {
        environment.board.draggingTaskID = task.id
        return TaskDragItem(taskID: task.id)
    }

    @ViewBuilder
    private var metadataRow: some View {
        if runtimeState != .notStarted || task.runContext == .worktree {
            HStack(spacing: 10) {
                if runtimeState != .notStarted {
                    StatusBadge(systemImage: runtimeState.systemImage, text: runtimeState.label)
                }
                if task.runContext == .worktree {
                    StatusBadge(systemImage: "arrow.triangle.branch", text: "Worktree")
                }
            }
        }
    }
}
