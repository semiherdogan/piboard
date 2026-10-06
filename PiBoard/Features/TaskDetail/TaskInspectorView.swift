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
                    TextField("Title", text: titleBinding(for: taskIndex))
                        .labelsHidden()
                }

                Section("Prompt") {
                    PromptEditor(text: promptBinding(for: taskIndex))
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

    private func titleBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { board.tasks[index].title },
            set: { board.tasks[index].title = $0 }
        )
    }

    private func promptBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { board.tasks[index].prompt },
            set: { board.tasks[index].prompt = $0 }
        )
    }

    private func statusBinding(for task: BoardTask) -> Binding<TaskStatus> {
        Binding(
            get: { task.status },
            set: { newStatus in
                guard newStatus != task.status else { return }
                let targetCount = board.tasks(for: task.projectId, status: newStatus).count
                board.move(taskID: task.id, to: newStatus, at: targetCount)
            }
        )
    }

    @ViewBuilder
    private func runtimeRow(for task: BoardTask) -> some View {
        let state = board.runtimeStates[task.id] ?? .notStarted
        LabeledContent("State") {
            Label(state.label, systemImage: state.systemImage)
        }
    }
}
