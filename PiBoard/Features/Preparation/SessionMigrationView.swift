import SwiftUI

private let migrationSheetWidth: CGFloat = 560
private let migrationSheetHeight: CGFloat = 640
private let summaryMinHeight: CGFloat = 260
private let migratingMessage = "Preparing session..."
private let currentTreeTitle = RunContext.current.title
private let editedSummaryHelp = "The summary was edited by hand."
private let migrateButtonTitle = "Migrate"
private let handOffButtonTitle = "Hand Off"

struct SessionMigrationView: View {
    let migration: BoardModel.PendingMigration
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var handoffText = ""
    @State private var lastRendered = ""
    @State private var isEdited = false
    @State private var transcript = SessionTranscript()
    @State private var isLoading = true
    @State private var readFailed = false
    // The task as it was when the sheet opened; the live task changes agent once the migration is written.
    @State private var sourceTask: BoardTask?
    @State private var includeAssistantReplies = SessionHandoffOptions().includeAssistantReplies
    @State private var includeChangedFiles = SessionHandoffOptions().includeChangedFiles
    @State private var planFirst = false
    @State private var sharesCurrentTree = false
    @State private var isBusy = false
    @State private var errorMessage: String?

    private enum Readiness {
        case runtimeMissing
        case projectPathMissing
        case worktreeMissing
        case currentTreeBusy
        case ready
    }

    private var board: BoardModel { environment.board }

    private var target: AgentKind { migration.target }

    private var task: BoardTask? {
        sourceTask ?? board.tasks.first { $0.id == migration.taskID }
    }

    private var project: Project? {
        guard let task else { return nil }
        return board.projects.first { $0.id == task.projectId }
    }

    private var launch: (context: RunContext, cwd: URL)? {
        guard let task, let project else { return nil }
        return SessionMigration.launchDirectory(task: task, project: project)
    }

    private var isEmptySummary: Bool {
        handoffText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if let task, let project {
                Form {
                    headerSection(task: task)
                    summarySection(task: task)
                    optionsSection
                    runSection(task: task, project: project)
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView("Task Not Found", systemImage: "exclamationmark.triangle")
            }
            footer
                .padding(20)
        }
        .frame(width: migrationSheetWidth, height: migrationSheetHeight)
        .task(id: migration) {
            await load()
        }
        .onAppear {
            planFirst = environment.preferences.planFirstEnabled
        }
        .onChange(of: includeAssistantReplies) { _, _ in rerender() }
        .onChange(of: includeChangedFiles) { _, _ in rerender() }
        .onChange(of: handoffText) { _, newValue in
            if newValue != lastRendered { isEdited = true }
        }
    }

    private func headerSection(task: BoardTask) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(headerTitle(task: task))
                    .font(.title3.weight(.semibold))
                Text(headerCaption(task: task))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func headerTitle(task: BoardTask) -> String {
        if task.agent == target {
            return "Hand off \"\(task.title)\" to a new \(target.title) session"
        }
        return "Migrate \"\(task.title)\" from \(task.agent.title) to \(target.title)"
    }

    private func headerCaption(task: BoardTask) -> String {
        if task.agent == target {
            return "\(target.title) starts a new session with the summary below as its first prompt. The current session stays on disk and is removed when the task is deleted."
        }
        return "\(target.title) starts a new session with the summary below as its first prompt. The \(task.agent.title) session stays on disk and is removed when the task is deleted."
    }

    private func summarySection(task: BoardTask) -> some View {
        Section("Summary") {
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Reading the \(task.agent.title) session...")
                        .foregroundStyle(.secondary)
                }
            } else {
                if readFailed {
                    Label("Could not read the \(task.agent.title) session.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                PromptEditor(text: $handoffText, minHeight: summaryMinHeight)
                    .accessibilityIdentifier(AccessibilityID.migrationSummary)
            }
        }
    }

    private var optionsSection: some View {
        Section("Options") {
            Toggle("Include assistant replies", isOn: $includeAssistantReplies)
                .disabled(isEdited || isLoading || isBusy)
                .help(isEdited ? editedSummaryHelp : "")
            Toggle("Include changed files", isOn: $includeChangedFiles)
                .disabled(isEdited || isLoading || isBusy)
                .help(isEdited ? editedSummaryHelp : "")
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Plan first", isOn: $planFirst)
                Text(planFirstCaption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .disabled(isBusy)
        }
    }

    private var planFirstCaption: String {
        environment.preferences.planFirstSuffix.components(separatedBy: .newlines).first ?? ""
    }

    @ViewBuilder
    private func runSection(task: BoardTask, project: Project) -> some View {
        let launch = SessionMigration.launchDirectory(task: task, project: project)
        Section("Run") {
            LabeledContent("Run Context", value: runContextDescription(task: task, context: launch.context))
            Text(AgentStrings.willRunIn(path: ProjectPathService.abbreviated(launch.cwd), target))
                .font(.caption)
                .foregroundStyle(.secondary)
            readinessLine
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func runContextDescription(task: BoardTask, context: RunContext) -> String {
        guard context == .worktree else { return currentTreeTitle }
        return task.worktreeBranch.map { "Existing worktree \($0)" } ?? "Existing worktree"
    }

    @ViewBuilder
    private var readinessLine: some View {
        switch readiness {
        case .runtimeMissing:
            HStack {
                Label(AgentStrings.runtimeNotInstalledSentence(target), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Spacer()
                SettingsLink {
                    Text("Open Settings")
                }
            }
        case .projectPathMissing:
            Label("Project folder is missing. Locate it first.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .worktreeMissing:
            Label("The task's worktree folder is missing.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .currentTreeBusy:
            Label(AgentStrings.currentTreeBusy(target), systemImage: "lock.fill")
                .foregroundStyle(.orange)
        case .ready:
            if sharesCurrentTree {
                Text("Both agents will edit the same files. Use this for questions, not for changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if isBusy {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(migratingMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .disabled(isBusy)
                .accessibilityIdentifier(AccessibilityID.sheetCancel)
            if case .currentTreeBusy = readiness {
                Button("Start Anyway") { sharesCurrentTree = true }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                    .accessibilityIdentifier(AccessibilityID.migrationStartAnyway)
            }
            Button(task?.agent == target ? handOffButtonTitle : migrateButtonTitle) { migrate() }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || isBusy || isEmptySummary || !isReady)
                .accessibilityIdentifier(AccessibilityID.migrationStart)
        }
    }

    private var readiness: Readiness {
        guard case .ready = environment.runtime(for: target).status else { return .runtimeMissing }
        guard let project, let launch, ProjectPathService.exists(project.path) else { return .projectPathMissing }
        guard ProjectPathService.exists(launch.cwd) else { return .worktreeMissing }
        if launch.context == .current, !sharesCurrentTree,
           let owner = environment.processes.currentTreeOwners[AgentProcessManager.canonicalPath(project.path)],
           owner != migration.taskID {
            return .currentTreeBusy
        }
        return .ready
    }

    private var isReady: Bool {
        if case .ready = readiness { return true }
        return false
    }

    private func load() async {
        guard let task = board.tasks.first(where: { $0.id == migration.taskID }),
              let project = board.projects.first(where: { $0.id == task.projectId }),
              let sessionID = task.sessionID else {
            isLoading = false
            return
        }
        sourceTask = task
        isLoading = true
        // Same cwd rule as SessionSummaryStore.refresh: it decides the source's sessions folder.
        let cwd = task.runContext == .worktree ? (task.worktreePath ?? project.path) : project.path
        let loaded = await environment.agents.adapter(for: task.agent).readSessionTranscript(id: sessionID, cwd: cwd)
        guard !Task.isCancelled else { return }
        readFailed = loaded == nil
        transcript = loaded ?? SessionTranscript()
        isEdited = false
        rerender()
        isLoading = false
    }

    private func render() -> String {
        guard let task else { return "" }
        let handoff = SessionHandoff(
            sourceAgent: task.agent,
            taskTitle: task.title,
            taskPrompt: task.prompt,
            transcript: transcript
        )
        let options = SessionHandoffOptions(
            includeAssistantReplies: includeAssistantReplies,
            includeChangedFiles: includeChangedFiles
        )
        return SessionHandoffRenderer.render(handoff, options: options)
    }

    private func rerender() {
        guard !isEdited else { return }
        let rendered = render()
        lastRendered = rendered
        handoffText = rendered
    }

    private func migrate() {
        guard let task, let project, let launch else { return }
        errorMessage = nil
        isBusy = true
        let adapter = environment.agents.adapter(for: target)
        let sessionID = adapter.makeSessionID()
        let target = target
        let originalRunContext = task.runContext
        Task {
            defer { isBusy = false }
            // The target-side session comes first so a failed call leaves nothing written.
            do {
                try await adapter.prepareSession(id: sessionID, title: task.title, cwd: launch.cwd)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
            board.migrateTask(task.id, to: target, newSessionID: sessionID)
            board.setRunContext(launch.context, for: task.id)
            // The manager picks the adapter from the task, so it needs the migrated copy.
            guard let updatedTask = board.tasks.first(where: { $0.id == task.id }) else { return }
            let launchPrompt = PromptComposer.compose(
                prompt: handoffText,
                planFirst: planFirst,
                suffix: environment.preferences.planFirstSuffix
            )
            do {
                _ = try environment.processes.start(
                    task: updatedTask,
                    project: project,
                    runContext: launch.context,
                    cwd: launch.cwd,
                    prompt: launchPrompt,
                    sessionID: sessionID,
                    sharesCurrentTree: sharesCurrentTree
                )
                environment.attention.clear(taskID: task.id)
                environment.sessionSummaries.forget(taskID: task.id)
                board.terminalToOpenAfterPreparation = task.id
                dismiss()
            } catch {
                board.undoMigration(task.id)
                if let originalRunContext {
                    board.setRunContext(originalRunContext, for: task.id)
                }
                try? await adapter.deleteSession(id: sessionID, cwd: launch.cwd)
                errorMessage = error.localizedDescription
            }
        }
    }
}
