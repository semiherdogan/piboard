import SwiftUI

struct TaskCardView: View {
    let task: BoardTask
    @Environment(AppEnvironment.self) private var environment
    @State private var isHovered = false

    private var isSelected: Bool {
        environment.board.selectedTaskID == task.id
    }

    private var runtimeState: TaskRuntimeState {
        environment.processes.runtimeState(for: task.id)
    }

    private var hasSession: Bool {
        task.piSessionId != nil || environment.processes.session(for: task.id) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
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
                }
                Spacer(minLength: 0)
                if task.status == .inProgress, hasSession {
                    Button {
                        environment.board.openTerminalTaskID = task.id
                    } label: {
                        Image(systemName: "terminal")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Open Terminal")
                }
            }

            metadataRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .surfaceCard(isSelected: isSelected, isHovered: isHovered)
        .contentShape(Rectangle())
        .onTapGesture {
            environment.board.selectedTaskID = task.id
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                environment.board.isInspectorPresented = true
            }
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .draggable(dragItem())
        .contextMenu {
            if task.status == .inProgress {
                if hasSession {
                    Button("Open Terminal") {
                        environment.board.openTerminalTaskID = task.id
                    }
                } else {
                    Button("Prepare and Start Pi...") {
                        environment.board.pendingPreparationTaskID = task.id
                    }
                }
            }
            ForEach(TaskStatus.allCases.filter { $0 != task.status }, id: \.self) { status in
                Button("Move to \(status.title)") {
                    let targetCount = environment.board.tasks(for: task.projectId, status: status).count
                    environment.board.requestMove(taskID: task.id, to: status, at: targetCount, isRunning: isTaskRunning)
                }
            }
            Divider()
            Button("Delete Task", role: .destructive) {
                environment.board.taskPendingDeletion = task
            }
        }
    }

    private func isTaskRunning(_ taskID: UUID) -> Bool {
        let state = environment.processes.runtimeState(for: taskID)
        return state == .running || state == .starting
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
