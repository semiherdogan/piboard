import SwiftUI

struct TaskDetailView: View {
    let taskID: UUID
    @Environment(AppEnvironment.self) private var environment
    @State private var draft = TaskDraftEditor()

    private static let duplicateTitle = "Duplicate Task"
    private static let doneTitle = "Done"
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
    private static let migratedFromLabel = "Migrated from"
    private static let sheetWidth: CGFloat = 560
    private static let sheetHeight: CGFloat = 600

    private var board: BoardModel {
        environment.board
    }

    private var taskIndex: Int? {
        board.tasks.firstIndex { $0.id == taskID }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let taskIndex {
                form(for: board.tasks[taskIndex])
            } else {
                ContentUnavailableView("No Task Selected", systemImage: "square.text.square")
                    .frame(maxHeight: .infinity)
            }
            Divider()
            HStack {
                Spacer()
                Button(Self.doneTitle) { board.taskDetailID = nil }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(AccessibilityID.taskDetailDone)
            }
            .padding(16)
        }
        .frame(width: Self.sheetWidth, height: Self.sheetHeight)
        .onExitCommand { board.taskDetailID = nil }
    }

    @ViewBuilder
    private func form(for task: BoardTask) -> some View {
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
                if task.sessionID != nil {
                    LabeledContent("Agent") {
                        Label(task.agent.title, systemImage: task.agent.systemImage)
                    }
                }
                runtimeRow(for: task)
                LabeledContent("Run Context", value: task.runContext?.title ?? "Not set")
                if let branch = task.worktreeBranch {
                    LabeledContent("Branch") {
                        HStack {
                            Text(branch)
                            Button(WorktreeActions.removeMenuTitle) {
                                let worktreeActions = environment.worktreeActions
                                close { _ in worktreeActions.requestRemoval(for: task.id) }
                            }
                        }
                    }
                }
                if task.status == .inProgress {
                    if hasSession(task) {
                        Button("Open Terminal") {
                            close { $0.openTerminal(for: task.id) }
                        }
                    } else {
                        Button(AgentStrings.prepareAndStartNeutral) {
                            close { $0.pendingPreparationTaskID = task.id }
                        }
                    }
                }
                if SessionMigration.canMigrate(task, isRunning: environment.processes.runtimeState(for: task.id).isActive) {
                    let targets = SessionMigration.targets(for: task, enabled: environment.preferences.agentChoices)
                    if !targets.isEmpty {
                        Menu(AgentStrings.migrateMenuTitle) {
                            ForEach(targets, id: \.self) { kind in
                                Button(AgentStrings.migrateTo(kind, current: task.agent), systemImage: kind.systemImage) {
                                    close { $0.pendingMigration = BoardModel.PendingMigration(taskID: task.id, target: kind) }
                                }
                            }
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
                    if let previousAgent = task.previousAgent, let previousSessionID = task.previousSessionID {
                        LabeledContent(Self.migratedFromLabel, value: "\(previousAgent.title) \(previousSessionID.prefix(Self.sessionIDPrefixLength))")
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
                    // Looked up again so the dialog shows the title the flush just saved.
                    close { board in board.taskPendingDeletion = board.tasks.first { $0.id == task.id } }
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
        // The preparation sheet can save the prompt while this sheet is open; an idle
        // draft follows the stored value, a draft being typed keeps the user's text.
        .onChange(of: task.title) { _, newValue in
            if !draft.hasPendingChanges, draft.title != newValue { draft.load(title: newValue, prompt: task.prompt) }
        }
        .onChange(of: task.prompt) { _, newValue in
            if !draft.hasPendingChanges, draft.prompt != newValue { draft.load(title: task.title, prompt: newValue) }
        }
        .onDisappear { draft.flush() }
    }

    // Flushed first so a follow-up such as the preparation sheet reads the prompt just typed.
    // The follow-up gets the model as an argument because it runs after this view is gone.
    private func close(then action: @escaping @MainActor (BoardModel) -> Void) {
        let board = board
        draft.flush()
        board.closeTaskDetail { action(board) }
    }

    private func statusBinding(for task: BoardTask) -> Binding<TaskStatus> {
        let processes = environment.processes
        return Binding(
            get: { task.status },
            set: { newStatus in
                guard newStatus != task.status else { return }
                // Moving can open the preparation sheet or the stop-and-move dialog, so the sheet goes first.
                close { board in
                    let targetCount = board.tasks(for: task.projectId, status: newStatus).count
                    board.requestMove(taskID: task.id, to: newStatus, at: targetCount) { taskID in
                        let state = processes.runtimeState(for: taskID)
                        return state == .running || state == .starting
                    }
                }
            }
        )
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
