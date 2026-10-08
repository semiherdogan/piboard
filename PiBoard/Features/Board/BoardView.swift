import AppKit
import SwiftUI

struct BoardView: View {
    let project: Project
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openSettings) private var openSettings
    @State private var showsNewTaskSheet = false
    @State private var runtimeInstallError: String?
    @State private var showsFolderPicker = false
    @State private var showsEditProjectSheet = false
    @State private var dragController = BoardDragController()

    private var pathExists: Bool {
        ProjectPathService.exists(project.path)
    }

    // A filled symbol marks a shell still running behind a hidden drawer.
    private var terminalSystemImage: String {
        let isShellRunning = environment.shells.session(for: project.id)?.state.isRunning == true
        let isHidden = !environment.board.isTerminalDrawerPresented
        return isShellRunning && isHidden ? BoardTerminalDrawer.runningSystemImage : BoardTerminalDrawer.systemImage
    }

    private var isPathEditLocked: Bool {
        environment.processes.hasActiveCurrentTreeSession(projectPath: project.path)
    }

    private static let pathLockedMessage = "Stop the running Pi session before changing the project folder."

    var body: some View {
        VStack(spacing: 0) {
            header

            if showsRuntimeBanner {
                runtimeBanner
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }

            if !environment.orphanedProcesses.isEmpty {
                BannerView(
                    systemImage: "exclamationmark.triangle.fill",
                    title: "Pi processes still running",
                    message: "\(environment.orphanedProcesses.count) Pi process(es) from a previous PiBoard session are still running.",
                    actionTitle: "Stop Them",
                    action: { environment.stopOrphanedProcesses() },
                    secondaryActionTitle: "Ignore",
                    secondaryAction: { environment.ignoreOrphanedProcesses() }
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            if let lastError = environment.board.lastError {
                BannerView(
                    systemImage: "exclamationmark.triangle.fill",
                    title: "Something went wrong",
                    message: lastError,
                    actionTitle: "Dismiss",
                    action: { environment.board.lastError = nil }
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            if !pathExists {
                BannerView(
                    systemImage: "exclamationmark.triangle.fill",
                    title: "Project folder not found",
                    message: abbreviatedPath,
                    actionTitle: "Locate Folder...",
                    action: locateFolder,
                    actionDisabled: isPathEditLocked,
                    actionHelp: isPathEditLocked ? Self.pathLockedMessage : nil,
                    secondaryActionTitle: "Edit Project...",
                    secondaryAction: { showsEditProjectSheet = true }
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            let entries = columnEntries()
            HStack(alignment: .top, spacing: 16) {
                ForEach(TaskStatus.allCases, id: \.self) { status in
                    BoardColumnView(
                        status: status,
                        entries: entries[status] ?? [],
                        onClear: status == .done ? { environment.board.doneTasksPendingClear = project } : nil
                    )
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .named(BoardCoordinateSpace.name))
                        } action: { frame in
                            dragController.columnFrames[status] = frame
                        }
                }
            }
            .coordinateSpace(.named(BoardCoordinateSpace.name))
            // Owned by the always-mounted container so preview reordering can never unmount
            // the gesture mid-drag; card buttons and taps win plain clicks as child gestures.
            .gesture(boardDragGesture)
            .overlay(alignment: .topLeading) {
                BoardDragGhost()
            }
            .environment(dragController)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            if environment.board.isTerminalDrawerPresented {
                BoardTerminalDrawer(project: project)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDisappear {
            dragController.cancel()
        }
        .navigationTitle(project.name)
        .toolbar {
            ToolbarItem {
                let editor = environment.preferences.preferredEditor
                Button(ExternalAppActions.openTitle(editor), systemImage: editor.systemImage) {
                    environment.externalApps.open(project.path, in: editor)
                }
                .disabled(!pathExists || !environment.externalApps.isInstalled(editor))
            }
            ToolbarItem {
                Menu {
                    OpenInAllAppsMenuItems(target: project.path)
                } label: {
                    Label(ExternalAppActions.openInMenuTitle, systemImage: ExternalAppActions.openInMenuSystemImage)
                }
                .disabled(!pathExists)
            }
            ToolbarItem {
                Button(BoardTerminalDrawer.title, systemImage: terminalSystemImage) {
                    environment.toggleTerminalDrawer()
                }
                .disabled(!pathExists)
            }
            ToolbarItem {
                Button("New Task", systemImage: "plus") {
                    showsNewTaskSheet = true
                }
                .buttonStyle(.borderedProminent)
            }
            ToolbarItem {
                Menu {
                    Button("Edit Project...") {
                        showsEditProjectSheet = true
                    }
                    Button("Export Project...", action: exportProject)
                    Button("Delete Project...", role: .destructive) {
                        environment.board.projectPendingDeletion = project
                    }
                } label: {
                    Label("Project Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showsNewTaskSheet) {
            NewTaskSheet(projectID: project.id)
        }
        .sheet(isPresented: $showsEditProjectSheet) {
            EditProjectSheet(project: project)
        }
        .confirmationDialog(
            taskPendingDeletionTitle,
            isPresented: taskPendingDeletionBinding,
            presenting: environment.board.taskPendingDeletion
        ) { task in
            let plan = environment.deletions.plan(forTask: task)
            Button(plan.confirmTitle, role: .destructive) {
                deleteTaskPendingDeletion(task, plan: plan)
            }
            Button("Cancel", role: .cancel) {}
        } message: { task in
            Text(environment.deletions.plan(forTask: task).message)
        }
        .confirmationDialog(
            doneTasksPendingClearTitle,
            isPresented: doneTasksPendingClearBinding,
            presenting: environment.board.doneTasksPendingClear
        ) { project in
            let plan = environment.deletions.plan(forDoneTasksIn: project)
            Button(plan.confirmTitle, role: .destructive) {
                clearDoneTasks(plan: plan)
            }
            Button("Cancel", role: .cancel) {}
        } message: { project in
            Text(environment.deletions.plan(forDoneTasksIn: project).message)
        }
        .confirmationDialog(
            "Pi is still running for this task. Stop it and move?",
            isPresented: pendingMoveConfirmationBinding
        ) {
            Button("Stop and Move") {
                stopAndMovePendingConfirmation()
            }
            Button("Cancel", role: .cancel) {
                environment.board.cancelPendingMove()
            }
        }
        .worktreeRemovalDialog(environment.worktreeActions)
    }

    // While dragging, columns render the order the drop would produce so cards make room live.
    private func columnEntries() -> [TaskStatus: [BoardColumnEntry]] {
        let board = environment.board
        guard let draggingID = dragController.draggingTaskID,
              board.tasks.contains(where: { $0.id == draggingID && $0.projectId == project.id }) else {
            var entries: [TaskStatus: [BoardColumnEntry]] = [:]
            for status in TaskStatus.allCases {
                entries[status] = board.tasks(for: project.id, status: status).map { BoardColumnEntry(task: $0, role: .card) }
            }
            return entries
        }

        let projectTasks = board.tasks(for: project.id)
        let target = dragController.target
        let previewTasks = target.map {
            TaskOrdering.reorder(tasks: projectTasks, taskID: draggingID, to: $0.status, at: $0.index)
        } ?? projectTasks

        var entries: [TaskStatus: [BoardColumnEntry]] = [:]
        for status in TaskStatus.allCases {
            entries[status] = previewTasks
                .filter { $0.status == status }
                .sorted { $0.position < $1.position }
                .map { BoardColumnEntry(task: $0, role: $0.id == draggingID ? .placeholder : .card) }
        }

        return entries
    }

    private var boardDragGesture: some Gesture {
        DragGesture(
            minimumDistance: DragAppearance.minimumDragDistance,
            coordinateSpace: .named(BoardCoordinateSpace.name)
        )
        .onChanged { value in
            let board = environment.board
            let projectID = project.id
            if dragController.draggingTaskID == nil {
                // Frames of deleted tasks or other projects linger in cardFrames.
                let projectTaskIDs = Set(board.tasks(for: projectID).map(\.id))
                let frames = dragController.cardFrames.filter { projectTaskIDs.contains($0.key) }
                guard let taskID = BoardDragTargeting.hitTest(startLocation: value.startLocation, cardFrames: frames),
                      let frame = frames[taskID],
                      let task = board.tasks.first(where: { $0.id == taskID }) else { return }
                dragController.begin(taskID: taskID, location: value.startLocation, cardFrame: frame)
                Diagnostics.ui.info("drag begin task=\(taskID.uuidString, privacy: .public) source=\(task.status.rawValue, privacy: .public)")
            }
            dragController.update(location: value.location) { status in
                board.tasks(for: projectID, status: status).map(\.id)
            }
        }
        .onEnded { _ in
            guard dragController.draggingTaskID != nil else { return }
            guard let (taskID, target) = dragController.end() else {
                Diagnostics.ui.info("drag cancel")
                return
            }
            Diagnostics.ui.info("drag end task=\(taskID.uuidString, privacy: .public) target=\(target.status.rawValue, privacy: .public) index=\(target.index, privacy: .public)")
            withAnimation(.snappy) {
                environment.board.requestMove(taskID: taskID, to: target.status, at: target.index, isRunning: isTaskRunning)
            }
        }
    }

    private func isTaskRunning(_ taskID: UUID) -> Bool {
        let state = environment.processes.runtimeState(for: taskID)
        return state == .running || state == .starting
    }

    private var pendingMoveConfirmationBinding: Binding<Bool> {
        Binding(
            get: { environment.board.pendingMoveConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    environment.board.cancelPendingMove()
                }
            }
        )
    }

    private func stopAndMovePendingConfirmation() {
        if let pending = environment.board.pendingMoveConfirmation {
            environment.processes.stop(taskID: pending.taskID)
        }
        environment.board.confirmPendingMove()
    }

    private var taskPendingDeletionTitle: String {
        environment.board.taskPendingDeletion?.title ?? ""
    }

    private var taskPendingDeletionBinding: Binding<Bool> {
        Binding(
            get: { environment.board.taskPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    environment.board.taskPendingDeletion = nil
                }
            }
        )
    }

    private func deleteTaskPendingDeletion(_ task: BoardTask, plan: DeletionPlan) {
        let board = environment.board
        if board.selectedTaskID == task.id {
            board.isInspectorPresented = false
        }
        environment.deletions.delete(plan)
        board.taskPendingDeletion = nil
    }

    private var doneTasksPendingClearTitle: String {
        environment.board.doneTasksPendingClear.map { environment.deletions.plan(forDoneTasksIn: $0).title } ?? ""
    }

    private var doneTasksPendingClearBinding: Binding<Bool> {
        Binding(
            get: { environment.board.doneTasksPendingClear != nil },
            set: { isPresented in
                if !isPresented {
                    environment.board.doneTasksPendingClear = nil
                }
            }
        )
    }

    private func clearDoneTasks(plan: DeletionPlan) {
        let board = environment.board
        if let selectedTaskID = board.selectedTaskID, plan.taskIDs.contains(selectedTaskID) {
            board.isInspectorPresented = false
        }
        environment.deletions.delete(plan)
        board.doneTasksPendingClear = nil
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name)
                .font(.title2.weight(.semibold))
            HStack(spacing: 8) {
                Text(abbreviatedPath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(action: copyPath) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("Copy Path")
                Button(action: openInFinder) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .help("Open in Finder")
                .disabled(!pathExists)
            }
            if pathExists {
                ProjectGitStatusRow(project: project)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var abbreviatedPath: String {
        ProjectPathService.abbreviated(project.path)
    }

    private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(project.path.path, forType: .string)
    }

    private func openInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([project.path])
    }

    private struct BoardDragGhost: View {
        @Environment(AppEnvironment.self) private var environment
        @Environment(BoardDragController.self) private var drag

        var body: some View {
            ZStack(alignment: .topLeading) {
                if let draggingID = drag.draggingTaskID,
                   let task = environment.board.tasks.first(where: { $0.id == draggingID }) {
                    TaskCardView(task: task, role: .ghost)
                        .frame(width: drag.cardSize.width, height: drag.cardSize.height)
                        .scaleEffect(DragAppearance.ghostScale)
                        .shadow(
                            color: .black.opacity(DragAppearance.ghostShadowOpacity),
                            radius: DragAppearance.ghostShadowRadius,
                            y: DragAppearance.ghostShadowYOffset
                        )
                        .offset(
                            x: drag.dragLocation.x - drag.grabOffset.width,
                            y: drag.dragLocation.y - drag.grabOffset.height
                        )
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(DragAppearance.ghostFade, value: drag.draggingTaskID)
            .allowsHitTesting(false)
        }
    }

    // A failed update keeps the active version, so only a missing runtime blocks the board.
    private var showsRuntimeBanner: Bool {
        environment.piRuntime.status == .missing
    }

    private var runtimeBanner: some View {
        let runtime = environment.piRuntime
        let message: String = switch runtime.installPhase {
        case .installing(let version): "Installing Pi \(version)..."
        case .activating(let version): "Activating Pi \(version)..."
        case .failed(_, let reason): "Install failed: \(reason)"
        case .idle: runtimeInstallError ?? "Install Pi to start tasks. Your ~/.pi/agent settings are used as is."
        }
        return BannerView(
            systemImage: "shippingbox",
            title: "Pi runtime is not installed",
            message: message,
            actionTitle: "Install Pi",
            action: installPi,
            actionDisabled: runtime.isInstalling,
            secondaryActionTitle: "Open Settings",
            secondaryAction: { openSettings() }
        )
    }

    private func installPi() {
        runtimeInstallError = nil
        Task {
            do {
                try await environment.piRuntime.installLatest()
            } catch {
                runtimeInstallError = "Could not fetch latest Pi version: \(error.localizedDescription)"
            }
        }
    }

    private func exportProject() {
        do {
            try ProjectExportPanels.exportProject(project, from: environment.board)
        } catch {
            environment.board.lastError = "Could not export the project: \(error.localizedDescription)"
        }
    }

    private func locateFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            environment.board.updateProject(id: project.id, name: project.name, path: url)
        }
    }
}
