import SwiftUI

enum TaskCardRole {
    case card
    // The dragged task's slot in the live preview.
    case placeholder
    case ghost
}

struct TaskCardView: View {
    let task: BoardTask
    var role: TaskCardRole = .card
    @Environment(AppEnvironment.self) private var environment
    @Environment(BoardDragController.self) private var drag
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

    private var showsTerminalButton: Bool {
        task.status == .inProgress && hasSession
    }

    var body: some View {
        switch role {
        case .ghost:
            cardSurface(isHovered: false)
                .overlay(alignment: .topTrailing) { terminalButton }
        case .card, .placeholder:
            interactiveCard
        }
    }

    private var interactiveCard: some View {
        slot
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
            // Added after the tap gestures so clicking the button never selects the card.
            .overlay(alignment: .topTrailing) {
                if role == .card {
                    terminalButton
                }
            }
            .contextMenu {
                if task.status == .inProgress {
                    if hasSession {
                        Button("Open Terminal") {
                            environment.board.openTerminal(for: task.id)
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

    @ViewBuilder
    private var slot: some View {
        switch role {
        case .placeholder:
            RoundedRectangle(cornerRadius: DragAppearance.placeholderCornerRadius, style: .continuous)
                .fill(.quaternary)
                .overlay(
                    RoundedRectangle(cornerRadius: DragAppearance.placeholderCornerRadius, style: .continuous)
                        .strokeBorder(
                            .separator,
                            style: StrokeStyle(lineWidth: DragAppearance.placeholderLineWidth, dash: DragAppearance.placeholderDash)
                        )
                )
                .frame(maxWidth: .infinity)
                .frame(height: drag.cardSize.height)
        case .card, .ghost:
            cardSurface(isHovered: isHovered && drag.draggingTaskID == nil)
        }
    }

    private func cardSurface(isHovered: Bool) -> some View {
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
                if showsTerminalButton {
                    // Reserves the slot for terminalButton, which is drawn in an overlay.
                    Image(systemName: "terminal")
                        .hidden()
                }
            }

            metadataRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .surfaceCard(isSelected: isSelected, isHovered: isHovered)
    }

    @ViewBuilder
    private var terminalButton: some View {
        if showsTerminalButton {
            Button {
                environment.board.openTerminal(for: task.id)
            } label: {
                Image(systemName: "terminal")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open Terminal")
            .padding(12)
        }
    }

    private func isTaskRunning(_ taskID: UUID) -> Bool {
        let state = environment.processes.runtimeState(for: taskID)
        return state == .running || state == .starting
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
