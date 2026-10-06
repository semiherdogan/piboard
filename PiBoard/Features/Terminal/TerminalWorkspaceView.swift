import SwiftUI

private let headerHorizontalPadding: CGFloat = 16
private let headerVerticalPadding: CGFloat = 10
private let compactHeaderVerticalPadding: CGFloat = 6
private let headerDividerHeight: CGFloat = 20

struct TerminalWorkspaceView: View {
    let taskID: UUID
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Environment(AppEnvironment.self) private var environment
    @State private var isFocused = false
    @State private var isTerminalHovered = false
    @State private var showsStopConfirmation = false
    @State private var resumeError: String?
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

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .onChange(of: isFocused) { _, newValue in
            columnVisibility = newValue ? .detailOnly : .automatic
        }
        .task {
            await fetchCurrentBranch()
        }
    }

    @ViewBuilder
    private var header: some View {
        if let task, let project {
            if isFocused {
                compactHeader(task: task, project: project)
            } else {
                fullHeader(task: task, project: project)
            }
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
            StatusBadge(systemImage: runtimeState.systemImage, text: runtimeState.label)
            stopButton
            resumeButton(task: task)
            focusButton
        }
        .padding(.horizontal, headerHorizontalPadding)
        .padding(.vertical, headerVerticalPadding)
        .background(.bar)
    }

    private func compactHeader(task: BoardTask, project: Project) -> some View {
        HStack(spacing: 12) {
            backButton
            Divider().frame(height: headerDividerHeight)
            Text(task.title)
                .font(.subheadline.weight(.medium))
            Spacer()
            StatusBadge(systemImage: runtimeState.systemImage, text: runtimeState.label)
            stopButton
            resumeButton(task: task)
            focusButton
        }
        .padding(.horizontal, headerHorizontalPadding)
        .padding(.vertical, compactHeaderVerticalPadding)
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
        }
    }

    private var focusButton: some View {
        Button {
            isFocused.toggle()
        } label: {
            Image(systemName: isFocused ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            if let resumeError {
                Text(resumeError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            terminalArea
        }
    }

    @ViewBuilder
    private var terminalArea: some View {
        if let session {
            ZStack(alignment: .bottomTrailing) {
                TerminalHostView(taskID: taskID, session: session)
                if case .exited(let code) = session.state {
                    exitedOverlay(exitCode: code)
                }
                if isTerminalHovered {
                    expandButton
                }
            }
            .onHover { hovering in
                isTerminalHovered = hovering
            }
        } else {
            notRunningView
        }
    }

    private var expandButton: some View {
        Button {
            isFocused.toggle()
        } label: {
            Image(systemName: isFocused ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .padding(10)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(16)
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
                            ? "Resume to continue the previous session."
                            : "Start Pi from the task preparation."
                    )
                )
                if task.piSessionId != nil {
                    Button("Resume Pi") {
                        resume(task: task)
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

    private func resume(task: BoardTask) {
        resumeError = nil
        guard let project, let sessionID = task.piSessionId else { return }
        let runContext = task.runContext ?? .current
        let cwd: URL
        switch runContext {
        case .current:
            cwd = project.path
        case .worktree:
            // Never resume a worktree session in the project root.
            guard let worktreePath = task.worktreePath else {
                resumeError = "Worktree is missing or invalid. Reopen the task preparation to start fresh."
                return
            }
            cwd = worktreePath
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
