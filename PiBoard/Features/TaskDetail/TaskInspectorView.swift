import SwiftUI

struct TaskInspectorView: View {
    let taskID: UUID
    @Environment(AppEnvironment.self) private var environment
    @State private var draft = TaskDraftEditor()

    private static let duplicateTitle = "Duplicate Task"
    private static let sessionSectionTitle = "Session"
    private static let sessionIDLabel = "ID"
    private static let nameLabel = "Name"
    private static let turnsLabel = "Turns"
    private static let modelLabel = "Model"
    private static let tokensLabel = "Tokens"
    private static let costLabel = "Cost"
    private static let lastActivityLabel = "Last Activity"
    private static let noSummaryMessage = "Session file not read yet, or not found."
    private static let lastMessageLineLimit = 8
    private static let sessionIDPrefixLength = 8

    private var board: BoardModel {
        environment.board
    }

    private var taskIndex: Int? {
        board.tasks.firstIndex { $0.id == taskID }
    }

    var body: some View {
        if let taskIndex {
            let task = board.tasks[taskIndex]
            @Bindable var draft = draft
            Form {
                Section("Title") {
                    TextField("Title", text: $draft.title)
                        .labelsHidden()
                }

                Section("Prompt") {
                    PromptEditor(text: $draft.prompt)
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
                        LabeledContent("Branch") {
                            HStack {
                                Text(branch)
                                Button(WorktreeActions.removeMenuTitle) {
                                    environment.worktreeActions.requestRemoval(for: task.id)
                                }
                            }
                        }
                    }
                    if task.status == .inProgress {
                        if hasSession(task) {
                            Button("Open Terminal") {
                                board.openTerminal(for: task.id)
                            }
                        } else {
                            Button(AgentStrings.prepareAndStart(task.agent)) {
                                board.pendingPreparationTaskID = task.id
                            }
                        }
                    }
                }

                if let sessionID = task.sessionID {
                    Section(Self.sessionSectionTitle) {
                        LabeledContent(Self.sessionIDLabel) {
                            Text(String(sessionID.prefix(Self.sessionIDPrefixLength)))
                                .font(.caption.monospaced())
                        }
                        if let summary = environment.sessionSummaries.summary(for: task.id) {
                            if let name = summary.name { LabeledContent(Self.nameLabel, value: name) }
                            LabeledContent(Self.turnsLabel, value: "\(summary.turnCount)")
                            if let model = summary.model { LabeledContent(Self.modelLabel, value: model) }
                            LabeledContent(Self.tokensLabel, value: SessionSummaryPresentation.tokens(summary.usage))
                            if summary.usage.cost > 0 {
                                LabeledContent(Self.costLabel, value: SessionSummaryPresentation.cost(summary.usage.cost))
                            }
                            if let lastActivity = summary.lastActivity {
                                LabeledContent(Self.lastActivityLabel, value: lastActivity.formatted(.relative(presentation: .named)))
                            }
                            if let text = summary.lastAssistantText {
                                Text(text)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(Self.lastMessageLineLimit)
                                    .textSelection(.enabled)
                            }
                        } else {
                            Text(Self.noSummaryMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let project = board.projects.first(where: { $0.id == task.projectId }) {
                    let target = ExternalAppActions.targetURL(for: task, project: project)
                    Section("Open") {
                        OpenInPreferredAppsButtons(target: target)
                        Text(ProjectPathService.abbreviated(target))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Section {
                    Text("Created \(task.createdAt.formatted(.relative(presentation: .named))), updated \(task.updatedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button(Self.duplicateTitle) {
                        board.duplicateTask(task.id)
                    }
                    Button("Delete Task", role: .destructive) {
                        board.taskPendingDeletion = task
                    }
                }
            }
            .formStyle(.grouped)
            .task(id: task.sessionID) {
                if let project = board.projects.first(where: { $0.id == task.projectId }) {
                    environment.sessionSummaries.refresh(task: task, project: project)
                }
            }
            .task(id: taskID) {
                // Load first: it flushes a draft still pending for the previous task through the
                // previous closure before the closure is pointed at this task.
                draft.load(title: task.title, prompt: task.prompt)
                let board = board
                let taskID = taskID
                draft.onWrite = { title, prompt in
                    guard let stored = board.tasks.first(where: { $0.id == taskID }) else { return }
                    if stored.title != title { board.updateTitle(title, for: taskID) }
                    if stored.prompt != prompt { board.updatePrompt(prompt, for: taskID) }
                }
            }
            // The preparation sheet can save the prompt while the inspector is open; an idle
            // draft follows the stored value, a draft being typed keeps the user's text.
            .onChange(of: task.title) { _, newValue in
                if !draft.hasPendingChanges, draft.title != newValue { draft.load(title: newValue, prompt: task.prompt) }
            }
            .onChange(of: task.prompt) { _, newValue in
                if !draft.hasPendingChanges, draft.prompt != newValue { draft.load(title: task.title, prompt: newValue) }
            }
            .onDisappear { draft.flush() }
        } else {
            ContentUnavailableView("No Task Selected", systemImage: "square.text.square")
        }
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
        task.sessionID != nil || environment.processes.session(for: task.id) != nil
    }

    @ViewBuilder
    private func runtimeRow(for task: BoardTask) -> some View {
        let state = environment.processes.runtimeState(for: task.id)
        let badge = TaskPresentation.badge(
            for: task,
            runtimeState: state,
            worktreeExists: TaskPresentation.worktreeExists(for: task)
        )
        LabeledContent("State") {
            Label(badge?.label ?? state.label, systemImage: badge?.systemImage ?? state.systemImage)
        }
    }
}
