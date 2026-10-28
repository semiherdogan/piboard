import SwiftUI

private let sheetWidth: CGFloat = 560
private let sheetHeight: CGFloat = 510
// Room for the changed-files list or the missing-worktree banner.
private let expandedSheetHeight: CGFloat = 690
private let changedFilesMaxHeight: CGFloat = 140
private let preparingSessionMessage = "Preparing session..."

struct TaskPreparationView: View {
    let taskID: UUID
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var prompt: String = ""
    @State private var runContext: RunContext = .current
    @State private var agent: AgentKind = .default
    @State private var sharesCurrentTree = false
    @State private var errorMessage: String?
    @State private var showsStartFreshConfirmation = false
    @State private var planFirst: Bool = false
    @State private var preflight: PreflightState = .checking
    @State private var repositoryInfo: RepositoryInfo?
    // Non-nil while an async worktree step runs; disables every action.
    @State private var busyMessage: String?
    @State private var showsWorktreeInvalid = false
    @State private var worktreeInvalidReason: String?
    // Set when a resume was refused because the session file is gone; keeps the resolved launch target.
    @State private var missingSession: (sessionID: String, context: RunContext, cwd: URL)?
    @State private var showsStartFreshInCurrentTreeConfirmation = false

    private enum Readiness {
        case runtimeMissing
        case projectPathMissing
        case currentTreeBusy(ownerTaskID: UUID)
        case ready
    }

    private enum PreflightState: Equatable {
        case checking
        case ready
        case blocked(String)
        case dirty([GitChange])
        case notRepository
        case error(String)

        var logDescription: String {
            switch self {
            case .checking: "checking"
            case .ready: "ready"
            case .blocked(let reason): "blocked(\(reason))"
            case .dirty(let changes): "dirty(\(changes.count))"
            case .notRepository: "notRepository"
            case .error(let message): "error(\(message))"
            }
        }
    }

    private var board: BoardModel { environment.board }

    private var task: BoardTask? {
        board.tasks.first { $0.id == taskID }
    }

    private var project: Project? {
        guard let task else { return nil }
        return board.projects.first { $0.id == task.projectId }
    }

    private var isRepository: Bool {
        repositoryInfo?.isRepository ?? false
    }

    private var isBusy: Bool {
        busyMessage != nil
    }

    private var isDirtyCurrentTree: Bool {
        guard runContext == .current, case .dirty = preflight else { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let task, let project {
                header(task: task, project: project)
                promptSection
                agentSection(task: task)
                runInSection
                statusLine
                if showsWorktreeInvalid {
                    worktreeInvalidBanner(task: task, project: project)
                }
                if let missingSession {
                    SessionNotFoundBanner(
                        kind: task.agent,
                        sessionID: missingSession.sessionID,
                        actionDisabled: isBusy || !isReady(for: missingSession.context),
                        onStartFresh: {
                            self.missingSession = nil
                            launchNewSession(task: task, project: project, context: missingSession.context, cwd: missingSession.cwd)
                        },
                        onCancel: { dismiss() }
                    )
                }
                Spacer(minLength: 0)
                footer(task: task, project: project)
            } else {
                ContentUnavailableView("Task Not Found", systemImage: "exclamationmark.triangle")
            }
        }
        .padding(20)
        .frame(width: sheetWidth, height: isDirtyCurrentTree || showsWorktreeInvalid || missingSession != nil ? expandedSheetHeight : sheetHeight)
        .onAppear {
            runContext = .current
            agent = task?.agent ?? .default
            prompt = task?.prompt ?? ""
            planFirst = environment.preferences.planFirstEnabled
        }
        .task(id: runContext) {
            await runPreflight()
        }
        .onChange(of: runContext) { _, newValue in
            if newValue == .worktree { sharesCurrentTree = false }
        }
        .onChange(of: planFirst) { _, newValue in
            environment.preferences.planFirstEnabled = newValue
        }
        .onChange(of: agent) { _, newValue in
            guard let task, task.agent != newValue else { return }
            board.setAgent(newValue, for: task.id)
        }
    }

    private func header(task: BoardTask, project: Project) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.title)
                .font(.title3.weight(.semibold))
            Text("\(project.name) \u{B7} \(ProjectPathService.abbreviated(project.path))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Initial Prompt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                PromptTemplateMenu(prompt: $prompt)
            }
            PromptEditor(text: $prompt, minHeight: 100)
            planFirstSection
        }
    }

    private var planFirstSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Plan first", isOn: $planFirst)
                .toggleStyle(.checkbox)
            Text(planFirstCaption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var planFirstCaption: String {
        environment.preferences.planFirstSuffix.components(separatedBy: .newlines).first ?? ""
    }

    private func agentSection(task: BoardTask) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Agent", selection: $agent) {
                ForEach(AgentKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(task.sessionID != nil || isBusy)
            .accessibilityIdentifier(AccessibilityID.preparationAgentPicker)
            if task.sessionID != nil {
                Text("The session belongs to \(task.agent.title). Start Fresh to switch.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var runInSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Run in", selection: $runContext) {
                ForEach(RunContext.allCases, id: \.self) { context in
                    Text(context.title)
                        .tag(context)
                        .disabled(context == .worktree && !isRepository)
                }
            }
            .pickerStyle(.radioGroup)
            .disabled(isBusy)
            if preflight == .notRepository {
                Text("New Worktree: Not a Git repository")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch readiness(for: runContext) {
        case .runtimeMissing:
            HStack {
                Label(AgentStrings.runtimeNotInstalledSentence(task?.agent ?? .default), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Spacer()
                SettingsLink {
                    Text("Open Settings")
                }
            }
        case .projectPathMissing:
            Label("Project folder is missing. Locate it first.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .currentTreeBusy(let ownerTaskID):
            Label(AgentStrings.alreadyRunningInTree(owner: ownerTitle(for: ownerTaskID), task?.agent ?? .default), systemImage: "lock.fill")
                .foregroundStyle(.orange)
        case .ready:
            preflightStatus
        }
        if sharesCurrentTree, runContext == .current {
            Text("Both agents will edit the same files. Use this for questions, not for changes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var preflightStatus: some View {
        if let busyMessage {
            progressLabel(busyMessage)
        } else {
            switch preflight {
            case .checking:
                progressLabel("Checking working tree...")
            case .ready, .notRepository:
                Label("Ready to start.", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            case .blocked(let reason):
                Label(reason, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            case .dirty(let changes):
                if runContext == .current {
                    dirtyWarning(changes)
                } else {
                    Label("Ready to start.", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            case .error(let message):
                Label("Git check failed: \(message)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }

    private func progressLabel(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }

    private func dirtyWarning(_ changes: [GitChange]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Working tree has uncommitted changes")
                        .font(.callout.weight(.medium))
                    Text("^[\(changes.count) changed file](inflect: true)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(changes) { change in
                        Text("\(change.status) \(change.path)")
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: changedFilesMaxHeight)
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func worktreeInvalidBanner(task: BoardTask, project: Project) -> some View {
        BannerView(
            systemImage: "exclamationmark.triangle",
            title: "Worktree is missing or invalid",
            message: [
                task.worktreePath.map { "Expected at \(ProjectPathService.abbreviated($0))." } ?? "No worktree is recorded for this task.",
                worktreeInvalidReason,
            ].compactMap { $0 }.joined(separator: " "),
            actionTitle: "Start Fresh in Current Tree",
            action: { showsStartFreshInCurrentTreeConfirmation = true },
            actionDisabled: isBusy || !isReady(for: .current),
            secondaryActionTitle: "Cancel",
            secondaryAction: { dismiss() }
        )
        .confirmationDialog(
            AgentStrings.startNewSessionInCurrentTreeQuestion(task.agent),
            isPresented: $showsStartFreshInCurrentTreeConfirmation
        ) {
            Button("Start Fresh in Current Tree", role: .destructive) {
                board.clearWorktree(for: task.id)
                showsWorktreeInvalid = false
                runContext = .current
                launchNewSession(task: task, project: project, context: .current, cwd: project.path)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(AgentStrings.willRunIn(path: ProjectPathService.abbreviated(project.path), task.agent)) The previous worktree session can no longer be resumed from this task.")
        }
    }

    private func footer(task: BoardTask, project: Project) -> some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .disabled(isBusy)
                .accessibilityIdentifier(AccessibilityID.sheetCancel)
            if case .currentTreeBusy = readiness(for: task.runContext ?? runContext), !sharesCurrentTree {
                Button(task.sessionID != nil ? "Resume Anyway" : "Start Anyway") { sharesCurrentTree = true }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
            }
            if task.sessionID != nil {
                Button("Start Fresh") { showsStartFreshConfirmation = true }
                    .disabled(!canStart)
                Button(AgentStrings.resume(task.agent)) { resume(task: task, project: project) }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || !isReady(for: task.runContext ?? .current))
                    .accessibilityIdentifier(AccessibilityID.preparationResume)
            } else if isDirtyCurrentTree {
                Button("Use Worktree Instead") { runContext = .worktree }
                    .disabled(isBusy || !isRepository)
                Button("Run Anyway") {
                    launchNewSession(task: task, project: project, context: .current, cwd: project.path)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStart)
                .accessibilityIdentifier(AccessibilityID.preparationRunAnyway)
            } else {
                Button(AgentStrings.start(task.agent)) { start(task: task, project: project) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canStart)
                    .accessibilityIdentifier(AccessibilityID.preparationStart)
            }
        }
        .confirmationDialog(
            AgentStrings.startNewSessionQuestion(task.agent),
            isPresented: $showsStartFreshConfirmation
        ) {
            Button("Start Fresh", role: .destructive) {
                board.setSessionID(nil, for: task.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The previous session stays on disk and can no longer be resumed from this task. Pick the agent and run context, then start.")
        }
    }

    private func readiness(for context: RunContext) -> Readiness {
        guard let task, case .ready = environment.runtime(for: task.agent).status else { return .runtimeMissing }
        guard let project, ProjectPathService.exists(project.path) else { return .projectPathMissing }
        if context == .current, !sharesCurrentTree,
           let owner = environment.processes.currentTreeOwners[AgentProcessManager.canonicalPath(project.path)],
           owner != taskID {
            return .currentTreeBusy(ownerTaskID: owner)
        }
        return .ready
    }

    private func isReady(for context: RunContext) -> Bool {
        if case .ready = readiness(for: context) { return true }
        return false
    }

    private var canStart: Bool {
        guard isReady(for: runContext), !isBusy else { return false }
        switch preflight {
        case .checking, .blocked:
            return false
        case .ready, .dirty, .notRepository, .error:
            return runContext == .current || isRepository
        }
    }

    private func ownerTitle(for ownerTaskID: UUID) -> String {
        board.tasks.first { $0.id == ownerTaskID }?.title ?? "Another task"
    }

    private func runPreflight() async {
        guard let project else { return }
        let context = runContext
        let git = environment.git
        preflight = .checking

        var info: RepositoryInfo?
        let state: PreflightState
        if !ProjectPathService.exists(project.path) {
            state = .blocked("Project folder is missing. Locate it first.")
        } else {
            do {
                let repository = try await git.repositoryInfo(at: project.path)
                info = repository
                if !repository.isRepository {
                    state = .notRepository
                } else if context == .worktree {
                    // Worktrees branch from HEAD, so uncommitted changes do not affect them.
                    state = .ready
                } else {
                    let changes = try await git.status(at: project.path)
                    state = changes.isEmpty ? .ready : .dirty(changes)
                }
            } catch {
                state = .error(error.localizedDescription)
            }
        }

        // A newer run (run context changed) owns the result.
        guard !Task.isCancelled else { return }
        if let info {
            repositoryInfo = info
        }
        preflight = state
        Diagnostics.git.info("preflight task=\(taskID.uuidString, privacy: .public) context=\(context.rawValue, privacy: .public) result=\(state.logDescription, privacy: .public)")
    }

    private func start(task: BoardTask, project: Project) {
        switch runContext {
        case .current:
            launchNewSession(task: task, project: project, context: .current, cwd: project.path)
        case .worktree:
            startInWorktree(task: task, project: project)
        }
    }

    // On failure the task stays In Progress without a running Pi; the error is shown inline.
    private func startInWorktree(task: BoardTask, project: Project) {
        errorMessage = nil
        busyMessage = "Creating worktree..."
        Task {
            do {
                let info = try await environment.worktrees.create(for: task, project: project)
                Diagnostics.git.info("worktree create ok task=\(task.id.uuidString, privacy: .public) path=\(info.path.path, privacy: .public) branch=\(info.branch, privacy: .public)")
                board.setWorktree(path: info.path, branch: info.branch, for: task.id)
                // launchNewSession takes over the busy state for the session step.
                launchNewSession(task: task, project: project, context: .worktree, cwd: info.path)
            } catch {
                busyMessage = nil
                Diagnostics.git.info("worktree create failed task=\(task.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                errorMessage = "Could not create the worktree: \(error.localizedDescription)"
            }
        }
    }

    private func launchNewSession(task: BoardTask, project: Project, context: RunContext, cwd: URL) {
        errorMessage = nil
        let adapter = environment.agents.adapter(for: task)
        let sessionID = adapter.makeSessionID()
        busyMessage = preparingSessionMessage
        Task {
            defer { busyMessage = nil }
            // The server-side session comes first so a failed call leaves no dangling id in SQLite.
            do {
                try await adapter.prepareSession(id: sessionID, title: task.title, cwd: cwd)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
            board.setSessionID(sessionID, for: task.id)
            board.setRunContext(context, for: task.id)
            board.updatePrompt(prompt, for: task.id)
            let launchPrompt = PromptComposer.compose(
                prompt: prompt,
                planFirst: planFirst,
                suffix: environment.preferences.planFirstSuffix
            )
            do {
                _ = try environment.processes.start(
                    task: task,
                    project: project,
                    runContext: context,
                    cwd: cwd,
                    prompt: launchPrompt,
                    sessionID: sessionID,
                    sharesCurrentTree: sharesCurrentTree
                )
                board.terminalToOpenAfterPreparation = task.id
                dismiss()
            } catch {
                // A session without a process would resume into an empty session and lose the prompt.
                board.setSessionID(nil, for: task.id)
                try? await adapter.deleteSession(id: sessionID, cwd: cwd)
                errorMessage = error.localizedDescription
            }
        }
    }

    // Resumes in the context the session was started in; the picker only affects new sessions.
    private func resume(task: BoardTask, project: Project) {
        errorMessage = nil
        showsWorktreeInvalid = false
        worktreeInvalidReason = nil
        missingSession = nil
        let context = task.runContext ?? .current
        busyMessage = "Checking worktree..."
        Task {
            let outcome = await environment.sessionResumer.resume(task: task, project: project, sharesCurrentTree: sharesCurrentTree)
            busyMessage = nil
            switch outcome {
            case .started:
                board.terminalToOpenAfterPreparation = task.id
                dismiss()
            case .worktreeMissing:
                showsWorktreeInvalid = true
            case .worktreeInvalid(let reason):
                worktreeInvalidReason = reason
                showsWorktreeInvalid = true
            case .sessionNotFound(let sessionID, let cwd):
                missingSession = (sessionID, context, cwd)
            case .currentTreeBusy(let ownerTaskID):
                errorMessage = AgentProcessManager.LaunchError.currentTreeBusy(ownerTaskID: ownerTaskID, kind: task.agent).localizedDescription
            case .failed(let message):
                errorMessage = message
            }
        }
    }
}
