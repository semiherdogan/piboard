import AppKit
import SwiftUI

struct BoardView: View {
    let project: Project
    @Environment(AppEnvironment.self) private var environment
    @State private var showsNewTaskSheet = false
    @State private var showsFolderPicker = false
    @State private var showsEditProjectSheet = false
    @State private var dragController = BoardDragController()

    private var pathExists: Bool {
        ProjectPathService.exists(project.path)
    }

    private var isPathEditLocked: Bool {
        environment.processes.hasActiveCurrentTreeSession(projectPath: project.path)
    }

    private static let pathLockedMessage = "Stop the running Pi session before changing the project folder."

    var body: some View {
        VStack(spacing: 0) {
            header

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
                    BoardColumnView(status: status, entries: entries[status] ?? [])
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
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDisappear {
            dragController.cancel()
        }
        .navigationTitle(project.name)
        .toolbar {
            ToolbarItem {
                Button("Open in VS Code", systemImage: "chevron.left.forwardslash.chevron.right") {}
                    .disabled(true)
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
            Button("Delete Task", role: .destructive) {
                deleteTaskPendingDeletion(task)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This removes the task from the board. Pi session files are not deleted.")
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

    private func deleteTaskPendingDeletion(_ task: BoardTask) {
        let board = environment.board
        if board.selectedTaskID == task.id {
            board.isInspectorPresented = false
        }
        board.deleteTask(task.id)
        board.taskPendingDeletion = nil
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
