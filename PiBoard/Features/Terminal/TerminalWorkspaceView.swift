import SwiftUI

private let headerHorizontalPadding: CGFloat = 16
private let headerVerticalPadding: CGFloat = 10
private let headerDividerHeight: CGFloat = 20
private let terminalMinWidth: CGFloat = 480

struct TerminalWorkspaceView: View {
    let taskID: UUID
    @Environment(AppEnvironment.self) private var environment
    @State private var showsStopConfirmation = false
    @State private var resumeError: String?
    @State private var isCheckingResume = false
    @State private var dragStartWidth: Double?
    // Set when a resume was refused because the session file is gone; holds the resolved cwd.
    @State private var missingSession: (sessionID: UUID, cwd: URL)?
    // Fetched once per appearance for current-tree tasks; worktree tasks show their stored branch.
    @State private var currentBranch: String?

    private var board: BoardModel { environment.board }

    private var task: BoardTask? {
        board.tasks.first { $0.id == taskID }
    }

    private var project: Project? {
        guard let task else { return nil }
        return board.projects.first { $0.id == task.projectId }
    }

    private var runtimeState: TaskRuntimeState {
        environment.processes.runtimeState(for: taskID)
    }

    private var session: PTYSession? {
        environment.processes.session(for: taskID)
    }

    private func headerBadge(task: BoardTask) -> some View {
        let badge = TaskPresentation.headerBadge(
            for: task,
            runtimeState: runtimeState,
            agentActivity: environment.processes.agentActivity(for: taskID)
        )
        return StatusBadge(systemImage: badge.systemImage, text: badge.label)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .task(id: taskID) {
            // A saved session is always resumed on open; Stop and crashes stay manual so a failing Pi cannot loop.
            resumeIfNeeded()
            DispatchQueue.main.async { session?.focusTerminal() }
            await fetchCurrentBranch()
        }
        // Attach-time focus is not enough: the view can appear after other controls already took the keyboard.
        .onChange(of: session?.state) { _, state in
            guard state?.isRunning == true else { return }
            DispatchQueue.main.async { session?.focusTerminal() }
        }
        .onChange(of: board.isTerminalDrawerPresented) { _, isPresented in
            guard !isPresented else { return }
            DispatchQueue.main.async { session?.focusTerminal() }
        }
        .worktreeRemovalDialog(environment.worktreeActions)
    }

    @ViewBuilder
    private var header: some View {
        if let task, let project {
            fullHeader(task: task, project: project)
        } else {
            HStack {
                backButton
                Spacer()
            }
            .padding(.horizontal, headerHorizontalPadding)
            .padding(.vertical, headerVerticalPadding)
            .background(.bar)
        }
    }

    private func fullHeader(task: BoardTask, project: Project) -> some View {
        HStack(spacing: 12) {
            backButton
            Divider().frame(height: headerDividerHeight)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.headline)
                Text(subtitle(task: task, project: project))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            headerBadge(task: task)
            stopButton
            resumeButton(task: task)
            findButton
            editorButton(task: task, project: project)
            overflowMenu(task: task)
        }
        .padding(.horizontal, headerHorizontalPadding)
        .padding(.vertical, headerVerticalPadding)
        .background(.bar)
    }

    private var backButton: some View {
        Button {
            board.openTerminalTaskID = nil
        } label: {
            Label("Back to Board", systemImage: "chevron.left")
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.plain)
    }

    private var stopButton: some View {
        Button("Stop Pi", role: .destructive) {
            showsStopConfirmation = true
        }
        .disabled(!(runtimeState == .running || runtimeState == .starting))
        .confirmationDialog(
            "Stop the Pi process for this task?",
            isPresented: $showsStopConfirmation
        ) {
            Button("Stop Pi", role: .destructive) {
                environment.processes.stop(taskID: taskID)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func resumeButton(task: BoardTask) -> some View {
        if case .exited = runtimeState, task.piSessionId != nil {
            Button("Resume Pi") {
                resume(task: task)
            }
            .disabled(isCheckingResume)
        }
    }

    private var findButton: some View {
        Button {
            environment.showTerminalFindBar()
        } label: {
            Image(systemName: TerminalFind.systemImage)
        }
        .buttonStyle(.plain)
        .disabled(session == nil)
        .help(TerminalFind.buttonHelp)
    }

    // The preferred terminal is reachable from the terminal drawer, so only the editor gets a header button.
    private func editorButton(task: BoardTask, project: Project) -> some View {
        let editor = environment.preferences.preferredEditor
        let actions = environment.externalApps
        let target = ExternalAppActions.targetURL(for: task, project: project)
        return Button {
            actions.open(target, in: editor)
        } label: {
            Image(systemName: editor.systemImage)
        }
        .buttonStyle(.plain)
        .disabled(!actions.isInstalled(editor) || !ProjectPathService.exists(target))
        .help(ExternalAppActions.openTitle(editor))
    }

    @ViewBuilder
    private func overflowMenu(task: BoardTask) -> some View {
        if task.worktreePath != nil {
            Menu {
                Button(WorktreeActions.removeMenuTitle, role: .destructive) {
                    environment.worktreeActions.requestRemoval(for: task.id)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            if let lastError = board.lastError {
                BannerView(
                    systemImage: "exclamationmark.triangle.fill",
                    title: "Something went wrong",
                    message: lastError,
                    actionTitle: "Dismiss",
                    action: { board.lastError = nil }
                )
                .padding(8)
            }
            if let missingSession, let task, let project {
                SessionNotFoundBanner(
                    sessionID: missingSession.sessionID,
                    onStartFresh: { startFresh(task: task, project: project, cwd: missingSession.cwd) },
                    onCancel: { self.missingSession = nil }
                )
                .padding(8)
            }
            if let resumeError {
                Text(resumeError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 0) {
                terminalArea
                    .frame(minWidth: terminalMinWidth, maxWidth: .infinity, maxHeight: .infinity)
                if board.isChangesPanelPresented, let task, let project {
                    changesDivider
                    TerminalChangesPanel(
                        path: ExternalAppActions.targetURL(for: task, project: project),
                        taskID: taskID,
                        title: task.title
                    )
                    .frame(width: environment.preferences.changesPanelWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if board.isTerminalDrawerPresented, let project {
                BoardTerminalDrawer(project: project)
            }
        }
    }

    // Dragging left widens the panel, so the delta is subtracted. The width is read at drag
    // start and written through the preference so it is already persisted when the drag ends.
    private var changesDivider: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: ChangesPanelWidth.dividerWidth)
            .frame(width: ChangesPanelWidth.dividerHitWidth)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = environment.preferences.changesPanelWidth
                        }
                        let proposed = (dragStartWidth ?? ChangesPanelWidth.defaultValue) - value.translation.width
                        environment.preferences.changesPanelWidth = proposed.clamped(to: ChangesPanelWidth.minimum...ChangesPanelWidth.maximum)
                    }
                    .onEnded { _ in dragStartWidth = nil }
            )
    }

    @ViewBuilder
    private var terminalArea: some View {
        if let session {
            ZStack(alignment: .bottomTrailing) {
                TerminalHostView(taskID: taskID, session: session)
                if case .exited(let code) = session.state {
                    exitedOverlay(exitCode: code)
                }
            }
        } else {
            notRunningView
        }
    }

    @ViewBuilder
    private var notRunningView: some View {
        if let task {
            VStack(spacing: 12) {
                ContentUnavailableView(
                    "Pi is not running",
                    systemImage: "terminal",
                    description: Text(
                        task.piSessionId != nil
                            ? (isCheckingResume
                                ? "Resuming the previous session..."
                                : "Resume to continue the previous session.")
                            : "Start Pi from the task preparation."
                    )
                )
                if task.piSessionId != nil {
                    Button("Resume Pi") {
                        resume(task: task)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCheckingResume)
                } else {
                    Button("Prepare and Start") {
                        board.pendingPreparationTaskID = task.id
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("Task Not Found", systemImage: "exclamationmark.triangle")
        }
    }

    private func exitedOverlay(exitCode: Int32?) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(exitCode.map { "Pi exited (\($0))" } ?? "Pi exited")
                .font(.headline)
            HStack {
                if let task, task.piSessionId != nil {
                    Button("Resume Pi") {
                        resume(task: task)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCheckingResume)
                }
                Button("Back to Board") {
                    board.openTerminalTaskID = nil
                }
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pointerStyle(.default)
    }

    private func subtitle(task: BoardTask, project: Project) -> String {
        var parts = [Self.abbreviatedPath(project.path)]
        let branch = task.runContext == .worktree ? task.worktreeBranch : currentBranch
        if let branch {
            parts.append(branch)
        }
        if let runContext = task.runContext {
            parts.append(runContext.title)
        }
        return parts.joined(separator: " \u{B7} ")
    }

    private func fetchCurrentBranch() async {
        guard let task, task.runContext != .worktree, let project else { return }
        currentBranch = try? await environment.git.currentBranch(at: project.path)
    }

    private func resumeIfNeeded() {
        guard let task, task.piSessionId != nil, session == nil, runtimeState == .notStarted,
              !isCheckingResume, missingSession == nil, resumeError == nil
        else { return }
        resume(task: task)
    }

    private func resume(task: BoardTask) {
        resumeError = nil
        missingSession = nil
        guard let project, let sessionID = task.piSessionId else { return }
        let runContext = task.runContext ?? .current
        isCheckingResume = true
        Task {
            defer { isCheckingResume = false }
            let cwd: URL
            switch await WorktreeResumeCheck.run(task: task, project: project, worktrees: environment.worktrees) {
            case .ok(let resolved):
                cwd = resolved
            case .missing:
                resumeError = "Worktree is missing. Reopen the task preparation to start fresh."
                return
            case .invalid(let reason):
                resumeError = "Worktree is invalid: \(reason) Reopen the task preparation to start fresh."
                return
            }
            do {
                _ = try environment.processes.resume(
                    task: task,
                    project: project,
                    runContext: runContext,
                    cwd: cwd,
                    sessionID: sessionID,
                    runtime: environment.piRuntime
                )
            } catch PiProcessManager.LaunchError.sessionNotFound(let missingID) {
                missingSession = (missingID, cwd)
            } catch {
                resumeError = error.localizedDescription
            }
        }
    }

    private func startFresh(task: BoardTask, project: Project, cwd: URL) {
        missingSession = nil
        resumeError = nil
        let sessionID = UUID()
        board.setPiSessionID(sessionID, for: task.id)
        let prompt = PromptComposer.compose(
            prompt: task.prompt,
            planFirst: environment.preferences.planFirstEnabled,
            suffix: environment.preferences.planFirstSuffix
        )
        do {
            _ = try environment.processes.start(
                task: task,
                project: project,
                runContext: task.runContext ?? .current,
                cwd: cwd,
                prompt: prompt,
                sessionID: sessionID,
                runtime: environment.piRuntime
            )
        } catch {
            resumeError = error.localizedDescription
        }
    }

    private static func abbreviatedPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
