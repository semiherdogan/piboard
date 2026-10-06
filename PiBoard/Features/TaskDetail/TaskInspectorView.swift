import SwiftUI

struct TaskInspectorView: View {
    let taskID: UUID
    @Environment(AppEnvironment.self) private var environment

    private var board: BoardModel {
        environment.board
    }

    private var taskIndex: Int? {
        board.tasks.firstIndex { $0.id == taskID }
    }

    var body: some View {
        if let taskIndex {
            let task = board.tasks[taskIndex]
            Form {
                Section("Title") {
                    TextField("Title", text: titleBinding(for: task))
                        .labelsHidden()
                }

                Section("Prompt") {
                    PromptEditor(text: promptBinding(for: task))
                }

                Section("Status") {
                    Picker("Status", selection: statusBinding(for: task)) {
                        ForEach(TaskStatus.allCases, id: \.self) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section("Run") {
                    runtimeRow(for: task)
                    LabeledContent("Run Context", value: task.runContext?.title ?? "Not set")
                    if let branch = task.worktreeBranch {
                        LabeledContent("Branch", value: branch)
                    }
                    if let sessionID = task.piSessionId {
                        LabeledContent("Session") {
                            Text(String(sessionID.uuidString.prefix(8)))
                                .font(.caption.monospaced())
                        }
                    }
                    if task.status == .inProgress {
                        if hasSession(task) {
                            Button("Open Terminal") {
                                board.openTerminalTaskID = task.id
                            }
                        } else {
                            Button("Prepare and Start Pi...") {
                                board.pendingPreparationTaskID = task.id
                            }
                        }
                    }
                }

                Section {
                    Text("Created \(task.createdAt.formatted(.relative(presentation: .named))), updated \(task.updatedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Delete Task", role: .destructive) {
                        board.taskPendingDeletion = task
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("No Task Selected", systemImage: "square.text.square")
        }
    }

    private func titleBinding(for task: BoardTask) -> Binding<String> {
        Binding(
            get: { task.title },
            set: { board.updateTitle($0, for: task.id) }
        )
    }

    private func promptBinding(for task: BoardTask) -> Binding<String> {
        Binding(
            get: { task.prompt },
            set: { board.updatePrompt($0, for: task.id) }
        )
    }

    private func statusBinding(for task: BoardTask) -> Binding<TaskStatus> {
        Binding(
            get: { task.status },
            set: { newStatus in
                guard newStatus != task.status else { return }
                let targetCount = board.tasks(for: task.projectId, status: newStatus).count
                board.requestMove(taskID: task.id, to: newStatus, at: targetCount, isRunning: isTaskRunning)
            }
        )
    }

    private func isTaskRunning(_ taskID: UUID) -> Bool {
        let state = environment.processes.runtimeState(for: taskID)
        return state == .running || state == .starting
    }

    private func hasSession(_ task: BoardTask) -> Bool {
        task.piSessionId != nil || environment.processes.session(for: task.id) != nil
    }

    @ViewBuilder
    private func runtimeRow(for task: BoardTask) -> some View {
        let state = environment.processes.runtimeState(for: task.id)
        LabeledContent("State") {
            Label(state.label, systemImage: state.systemImage)
        }
    }
}
