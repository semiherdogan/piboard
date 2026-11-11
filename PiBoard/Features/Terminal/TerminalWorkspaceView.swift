import SwiftUI

private let headerHorizontalPadding: CGFloat = 16
private let headerVerticalPadding: CGFloat = 10
private let headerDividerHeight: CGFloat = 20
private let subtitleActionsSpacing: CGFloat = 10
private let interruptTitle = "Interrupt"
private let interruptSystemImage = "exclamationmark.octagon"
private let interruptHelp = "Interrupt the current turn (Ctrl-C)"
private let interfacePickerTitle = "Interface"
private let switchInterfaceMessage = "The running session is stopped and resumed in the other view. The conversation is kept."

struct TerminalWorkspaceView: View {
    let taskID: UUID
    @Environment(AppEnvironment.self) private var environment
    @State private var showsStopConfirmation = false
    // The interface the user picked while a session is running, awaiting confirmation.
    @State private var pendingInterface: SessionInterface?
    @State private var resumeError: String?
    @State private var currentTreeBusyOwner: UUID?
    @State private var sharesCurrentTree = false
    @State private var isCheckingResume = false
    @State private var dragStartWidth: Double?
    @State private var contentWidth: Double = 0
    // Set when a resume was refused because the session file is gone.
    @State private var missingSessionID: String?
    // Fetched once per appearance for current-tree tasks; worktree tasks show their stored branch.
    @State private var currentBranch: String?
    // The prompt last found and the term that found it; a different prompt starts again from the bottom.
    @State private var lastPromptSearch: (prompt: String, term: String)?
    // The repository's web page for the globe button; nil when there is no browsable remote.
    @State private var remoteURL: URL?
    // Nil while idle; set after a copy so the button shows the result for a moment.
    @State private var lastReplyCopied: Bool?

    private var board: BoardModel { environment.board }

    private var panelWidth: Double {
        ChangesPanelWidth.effective(preferred: environment.preferences.changesPanelWidth, available: contentWidth)
    }

    private var task: BoardTask? {
        board.tasks.first { $0.id == taskID }
    }

    private var agentKind: AgentKind { task?.agent ?? .default }

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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(badge.label)
            .accessibilityIdentifier(AccessibilityID.terminalStatus)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            // Keyed on the stored session id, which exists before the process does, so the strip
            // is in place before the terminal's first layout and never resizes the pty.
            if task?.sessionID != nil {
                SessionInfoStrip(
                    summary: environment.sessionSummaries.summary(for: taskID),
                    showsLastPrompt: environment.preferences.terminalShowsLastPrompt,
                    findPrompt: findInTerminal
                )
                Divider()
            }
            content
        }
        .task(id: taskID) {
            // Cleared before any await: this view is reused across tasks and must not offer the previous repository.
            remoteURL = nil
            // Read on open so the info strip is there before the first settle.
            environment.refreshSummary(taskID: taskID)
            // A saved session is always resumed on open; Stop and crashes stay manual so a failing Pi cannot loop.
            resumeIfNeeded()
            DispatchQueue.main.async { session?.focusTerminal() }
            await fetchCurrentBranch()
            await fetchRemoteURL()
        }
        // Attach-time focus is not enough: the view can appear after other controls already took the keyboard.
        .onChange(of: session?.state) { _, state in
            if case .exited = state {
                environment.refreshSummary(taskID: taskID)
            }
            guard state?.isRunning == true else { return }
            DispatchQueue.main.async { session?.focusTerminal() }
        }
        // The agent starts working right after a prompt is sent, so that is when the new prompt is on disk.
        .onChange(of: environment.processes.agentActivity(for: taskID)) { _, activity in
            if activity == .working { environment.refreshSummary(taskID: taskID) }
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
                    .lineLimit(1)
                HStack(spacing: subtitleActionsSpacing) {
                    Text(subtitle(task: task, project: project))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    PathActionButtons(path: ExternalAppActions.targetURL(for: task, project: project), remoteURL: remoteURL)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            headerBadge(task: task)
            interruptButton
            stopButton
            interfacePicker(task: task)
            resumeButton(task: task)
            if task.interface == .terminal {
                findButton
            }
            copyLastReplyButton(task: task)
            openInButton(task: task, project: project)
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
        .accessibilityIdentifier(AccessibilityID.backToBoard)
    }

    // No confirmation: unlike Stop, an interrupt keeps the session and Pi returns to its prompt.
    private var interruptButton: some View {
        Button {
            environment.processes.interrupt(taskID: taskID)
        } label: {
            Image(systemName: interruptSystemImage)
        }
        .buttonStyle(.plain)
        .disabled(runtimeState != .running)
        .help(interruptHelp)
        .accessibilityLabel(interruptTitle)
        .accessibilityIdentifier(AccessibilityID.terminalInterrupt)
    }

    private var stopButton: some View {
        Button(AgentStrings.stop(agentKind), role: .destructive) {
            showsStopConfirmation = true
        }
        .disabled(!(runtimeState == .running || runtimeState == .starting))
        .accessibilityIdentifier(AccessibilityID.terminalStop)
        .confirmationDialog(
            AgentStrings.stopProcessQuestion(agentKind),
            isPresented: $showsStopConfirmation
        ) {
            Button(AgentStrings.stop(agentKind), role: .destructive) {
                environment.processes.stop(taskID: taskID)
            }
            .accessibilityIdentifier(AccessibilityID.confirmDestructive)
            Button("Cancel", role: .cancel) {}
        }
    }

    // Only for a task that has a session: a fresh one picks its interface in the preparation sheet.
    @ViewBuilder
    private func interfacePicker(task: BoardTask) -> some View {
        if task.sessionID != nil, environment.agents.adapter(for: task).supportsConversation {
            Picker(interfacePickerTitle, selection: Binding(
                get: { task.interface },
                set: { requestSwitch(task: task, to: $0) }
            )) {
                ForEach(SessionInterface.allCases, id: \.self) { interface in
                    Text(interface.title).tag(interface)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(isCheckingResume)
            .accessibilityIdentifier(AccessibilityID.workspaceInterfacePicker)
            .confirmationDialog(
                pendingInterface.map { "Switch to \($0.title)?" } ?? "",
                isPresented: Binding(
                    get: { pendingInterface != nil },
                    set: { if !$0 { pendingInterface = nil } }
                ),
                presenting: pendingInterface
            ) { interface in
                Button("Switch to \(interface.title)", role: .destructive) {
                    switchInterface(task: task, to: interface)
                }
                .accessibilityIdentifier(AccessibilityID.confirmDestructive)
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text(switchInterfaceMessage)
            }
        }
    }

    @ViewBuilder
    private func resumeButton(task: BoardTask) -> some View {
        if case .exited = runtimeState, task.sessionID != nil {
            Button(AgentStrings.resume(task.agent)) {
                resume(task: task)
            }
            .disabled(isCheckingResume)
            .accessibilityIdentifier(AccessibilityID.terminalResume)
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

    private func copyLastReplyButton(task: BoardTask) -> some View {
        let systemImage = switch lastReplyCopied {
        case .none: LastReplyCopy.systemImage
        case .some(true): LastReplyCopy.succeededSystemImage
        case .some(false): LastReplyCopy.failedSystemImage
        }
        return Button {
            Task { lastReplyCopied = await environment.copyLastReply(taskID: taskID) }
        } label: {
            Image(systemName: systemImage)
        }
        .buttonStyle(.plain)
        .disabled(task.sessionID == nil)
        .help(LastReplyCopy.help)
        .accessibilityLabel(LastReplyCopy.title)
        .accessibilityIdentifier(AccessibilityID.terminalCopyLastReply)
        // Restarts only when the result changes; a repeated success keeps the running timer.
        .task(id: lastReplyCopied) {
            guard lastReplyCopied != nil, (try? await Task.sleep(for: LastReplyCopy.feedbackDuration)) != nil else { return }
            lastReplyCopied = nil
        }
    }

    // The header button opens the preferred editor and lists the rest; the terminal is also reachable from the drawer.
    private func openInButton(task: BoardTask, project: Project) -> some View {
        let editor = environment.preferences.preferredEditor
        let actions = environment.externalApps
        let target = ExternalAppActions.targetURL(for: task, project: project)
        return Menu {
            OpenInAllAppsMenuItems(target: target)
        } label: {
            if let icon = actions.icon(for: editor) {
                Image(nsImage: icon)
            } else {
                Image(systemName: editor.systemImage)
            }
        } primaryAction: {
            guard actions.isInstalled(editor) else { return }
            actions.open(target, in: editor)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.visible)
        .fixedSize()
        .disabled(!ProjectPathService.exists(target))
        .help(ExternalAppActions.openTitle(editor))
        .accessibilityLabel(ExternalAppActions.openInMenuTitle)
        .accessibilityIdentifier(AccessibilityID.terminalOpenIn)
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
            if let missingSessionID, let task {
                // The sheet shows the prompt and Plan first and confirms Start Fresh itself.
                SessionNotFoundBanner(
                    kind: task.agent,
                    sessionID: missingSessionID,
                    confirmsInline: false,
                    onStartFresh: {
                        self.missingSessionID = nil
                        board.pendingPreparationTaskID = task.id
                    },
                    onCancel: { self.missingSessionID = nil }
                )
                .padding(8)
            }
            if let currentTreeBusyOwner, let task {
                BannerView(
                    systemImage: "lock.fill",
                    title: AgentStrings.alreadyRunningInTree(owner: ownerTitle(for: currentTreeBusyOwner), task.agent),
                    message: "Resuming anyway runs both agents on the same files. Use this for questions, not for changes.",
                    actionTitle: "Resume Anyway",
                    action: {
                        sharesCurrentTree = true
                        resume(task: task)
                    }
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
                workspaceArea
                    .frame(minWidth: CGFloat(ChangesPanelWidth.terminalMinimum), maxWidth: .infinity, maxHeight: .infinity)
                if board.isChangesPanelPresented, let task, let project {
                    changesDivider
                    TerminalChangesPanel(
                        path: ExternalAppActions.targetURL(for: task, project: project),
                        taskID: taskID,
                        title: task.title
                    )
                    .frame(width: panelWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Measured on the frame, not the stack, so an overflowing child cannot inflate the reading.
            .onGeometryChange(for: Double.self) { proxy in proxy.size.width } action: { contentWidth = $0 }
            if board.isTerminalDrawerPresented, let project {
                BoardTerminalDrawer(project: project)
            }
        }
    }

    // Dragging left widens the panel, so the delta is subtracted. The drag starts from the width
    // on screen (not the stored one) and writes through the preference so it is persisted at the end.
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
                            dragStartWidth = panelWidth
                        }
                        let proposed = (dragStartWidth ?? ChangesPanelWidth.defaultValue) - value.translation.width
                        environment.preferences.changesPanelWidth = proposed.clamped(to: ChangesPanelWidth.minimum...ChangesPanelWidth.maximum)
                    }
                    .onEnded { _ in dragStartWidth = nil }
            )
    }

    @ViewBuilder
    private var workspaceArea: some View {
        switch task?.interface ?? .terminal {
        case .terminal:
            terminalArea
        case .chat:
            ConversationView(taskID: taskID, isCheckingResume: isCheckingResume) {
                if let task { resume(task: task) }
            }
        }
    }

    @ViewBuilder
    private var terminalArea: some View {
        if let session {
            ZStack(alignment: .bottomTrailing) {
                TerminalHostView(taskID: taskID, session: session)
                if case .exited(let code) = session.state {
                    SessionExitedOverlay(
                        task: task,
                        agentKind: agentKind,
                        exitCode: code,
                        isCheckingResume: isCheckingResume,
                        onResume: { if let task { resume(task: task) } }
                    )
                }
            }
        } else {
            notRunningView
        }
    }

    @ViewBuilder
    private var notRunningView: some View {
        if let task {
            SessionNotRunningView(task: task, isCheckingResume: isCheckingResume, onResume: { resume(task: task) })
        } else {
            ContentUnavailableView("Task Not Found", systemImage: "exclamationmark.triangle")
        }
    }

    private func subtitle(task: BoardTask, project: Project) -> String {
        var parts = [ProjectPathService.abbreviated(project.path)]
        let branch = task.runContext == .worktree ? task.worktreeBranch : currentBranch
        if let branch {
            parts.append(branch)
        }
        if let runContext = task.runContext {
            parts.append(runContext.title)
        }
        return parts.joined(separator: " \u{B7} ")
    }

    // Searches backwards; repeated clicks on the same prompt go further back with the term that matched,
    // wrapping to the newest again. A term that is gone (cleared terminal) starts the search over.
    private func findInTerminal(_ prompt: String) {
        guard let terminal = session?.terminalView else { return }
        if let previous = lastPromptSearch, previous.prompt == prompt, terminal.findPrevious(previous.term) {
            return
        }
        let terms = SessionSummaryPresentation.promptSearchTerms(prompt)
        for term in terms {
            // SwiftTerm starts from the current selection, so each new term starts again from the bottom.
            terminal.selectNone()
            if terminal.findPrevious(term) {
                lastPromptSearch = (prompt, term)
                return
            }
        }
        lastPromptSearch = nil
        // Full-screen agents such as OpenCode keep their history to themselves, so often there is nothing to find.
        NSSound.beep()
    }

    // Read once per opened task: a remote's address changes about once in a repository's life.
    private func fetchRemoteURL() async {
        guard let task, let project else { return }
        let remote = try? await environment.git.remoteBrowseURL(at: ExternalAppActions.targetURL(for: task, project: project))
        // A fetch for a task that was switched away from must not land on the next one.
        guard !Task.isCancelled else { return }
        remoteURL = remote
    }

    private func fetchCurrentBranch() async {
        guard let task, task.runContext != .worktree, let project else { return }
        currentBranch = try? await environment.git.currentBranch(at: project.path)
    }

    private func resumeIfNeeded() {
        guard let task, task.sessionID != nil, session == nil, environment.processes.conversation(for: taskID) == nil, runtimeState == .notStarted,
              !isCheckingResume, missingSessionID == nil, resumeError == nil, currentTreeBusyOwner == nil
        else { return }
        resume(task: task)
    }

    private func resume(task: BoardTask) {
        resumeError = nil
        currentTreeBusyOwner = nil
        missingSessionID = nil
        guard let project else { return }
        isCheckingResume = true
        Task {
            defer { isCheckingResume = false }
            show(await environment.sessionResumer.resume(task: task, project: project, sharesCurrentTree: sharesCurrentTree))
        }
    }

    private func requestSwitch(task: BoardTask, to interface: SessionInterface) {
        guard interface != task.interface else { return }
        if runtimeState.isActive {
            pendingInterface = interface
        } else {
            switchInterface(task: task, to: interface)
        }
    }

    private func switchInterface(task: BoardTask, to interface: SessionInterface) {
        resumeError = nil
        currentTreeBusyOwner = nil
        missingSessionID = nil
        guard let project else { return }
        isCheckingResume = true
        Task {
            defer { isCheckingResume = false }
            if let outcome = await environment.interfaceSwitcher.switchInterface(task: task, project: project, to: interface, sharesCurrentTree: sharesCurrentTree) {
                show(outcome)
            }
        }
    }

    private func show(_ outcome: ResumeOutcome) {
        switch outcome {
        case .started:
            break
        case .worktreeMissing:
            resumeError = "Worktree is missing. Reopen the task preparation to start fresh."
        case .worktreeInvalid(let reason):
            resumeError = "Worktree is invalid: \(reason) Reopen the task preparation to start fresh."
        case .sessionNotFound(let sessionID, _):
            missingSessionID = sessionID
        case .currentTreeBusy(let ownerTaskID):
            currentTreeBusyOwner = ownerTaskID
        case .failed(let message):
            resumeError = message
        }
    }

    private func ownerTitle(for taskID: UUID) -> String {
        board.tasks.first { $0.id == taskID }?.title ?? "Another task"
    }
}
