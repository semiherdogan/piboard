import SwiftUI

private let sidebarSystemImage = "sidebar.right"

struct MainWindow: View {
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @Environment(AppEnvironment.self) private var environment

    private var selectedProject: Project? {
        environment.board.projects.first { $0.id == environment.board.selectedProjectID }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ProjectSidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            VStack(spacing: 0) {
                if let startupError = environment.startupError {
                    BannerView(
                        systemImage: "externaldrive.badge.exclamationmark",
                        title: "Database problem",
                        message: startupError
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }

                if let taskID = environment.board.openTerminalTaskID {
                    TerminalWorkspaceView(taskID: taskID)
                        // Opening the terminal is the user seeing the agent's result, so the
                        // dot it raised has done its job.
                        .task(id: taskID) { environment.attention.clear(taskID: taskID) }
                        // An agent that settles while PiBoard is in the background marks the task even
                        // though its terminal is on screen; coming back to the app is seeing it.
                        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                            environment.attention.clear(taskID: taskID)
                        }
                } else if let selectedProject {
                    BoardView(project: selectedProject)
                } else {
                    ContentUnavailableView("Select a Project", systemImage: "sidebar.left")
                }
            }
        }
        .sheet(isPresented: taskDetailBinding, onDismiss: { environment.board.runAfterTaskDetailDismiss() }) {
            if let taskID = environment.board.taskDetailID {
                TaskDetailView(taskID: taskID)
            }
        }
        .sheet(isPresented: pendingPreparationBinding, onDismiss: moveTerminalToOpenAfterPreparation) {
            if let taskID = environment.board.pendingPreparationTaskID {
                TaskPreparationView(taskID: taskID)
            }
        }
        .sheet(item: migrationBinding, onDismiss: moveTerminalToOpenAfterPreparation) { migration in
            SessionMigrationView(migration: migration)
        }
        .sheet(item: commitRequestBinding) { request in
            CommitSheet(request: request)
        }
        .sheet(isPresented: commandPaletteBinding, onDismiss: { environment.board.runAfterCommandPaletteDismiss() }) {
            CommandPaletteView()
        }
        .toolbar {
            // Each screen gets its own item so the toolbar never reuses a stale one.
            if showsBoard {
                ToolbarItem {
                    Button(TaskDetailCommand.title, systemImage: TaskDetailCommand.systemImage) {
                        environment.board.taskDetailID = environment.board.selectedBoardTaskID
                    }
                    .help(TaskDetailCommand.title)
                    .disabled(environment.board.selectedBoardTaskID == nil)
                    .accessibilityIdentifier(AccessibilityID.taskDetailButton)
                }
            } else if environment.board.openTerminalTaskID != nil {
                ToolbarItem {
                    Button(TerminalChangesPanel.title, systemImage: sidebarSystemImage) {
                        environment.board.isChangesPanelPresented.toggle()
                    }
                    .help(TerminalChangesPanel.title)
                    .accessibilityIdentifier(AccessibilityID.changesToggle)
                }
            }
        }
        .confirmationDialog(
            projectPendingDeletionTitle,
            isPresented: projectPendingDeletionBinding,
            presenting: environment.board.projectPendingDeletion
        ) { project in
            let plan = environment.deletions.plan(forProject: project)
            Button(plan.confirmTitle, role: .destructive) {
                deleteProjectPendingDeletion(plan)
            }
            Button("Cancel", role: .cancel) {}
        } message: { project in
            Text(environment.deletions.plan(forProject: project).message)
        }
        .confirmationDialog(
            AgentStrings.stillWorkingQuestion(environment.board.taskPendingStop?.agent ?? .default),
            isPresented: taskPendingStopBinding,
            presenting: environment.board.taskPendingStop
        ) { task in
            Button(AgentStrings.stop(task.agent), role: .destructive) {
                environment.processes.stop(taskID: task.id)
                environment.board.taskPendingStop = nil
            }
            .accessibilityIdentifier(AccessibilityID.confirmDestructive)
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The current turn will be interrupted. The session can be resumed later.")
        }
        .frame(minWidth: 960, minHeight: 640)
    }

    private var showsBoard: Bool {
        environment.board.openTerminalTaskID == nil && selectedProject != nil
    }

    private var taskDetailBinding: Binding<Bool> {
        Binding(
            get: { environment.board.taskDetailID != nil },
            set: { isPresented in
                if !isPresented {
                    environment.board.taskDetailID = nil
                }
            }
        )
    }

    // The sheet owns a pty while pushing; dismissing through the binding terminates it.
    private var commitRequestBinding: Binding<CommitRequest?> {
        Binding(
            get: { environment.commits.request },
            set: { request in
                if request == nil {
                    environment.commits.dismiss()
                }
            }
        )
    }

    private var pendingPreparationBinding: Binding<Bool> {
        Binding(
            get: { environment.board.pendingPreparationTaskID != nil },
            set: { isPresented in
                if !isPresented {
                    environment.board.pendingPreparationTaskID = nil
                }
            }
        )
    }

    private var migrationBinding: Binding<BoardModel.PendingMigration?> {
        Binding(
            get: { environment.board.pendingMigration },
            set: { environment.board.pendingMigration = $0 }
        )
    }

    private var commandPaletteBinding: Binding<Bool> {
        Binding(
            get: { environment.board.isCommandPalettePresented },
            set: { environment.board.isCommandPalettePresented = $0 }
        )
    }

    private func moveTerminalToOpenAfterPreparation() {
        guard let taskID = environment.board.terminalToOpenAfterPreparation else { return }
        environment.board.terminalToOpenAfterPreparation = nil
        environment.board.openTerminal(for: taskID)
    }

    private var projectPendingDeletionTitle: String {
        if let name = environment.board.projectPendingDeletion?.name {
            return "Delete \"\(name)\"?"
        }
        return ""
    }

    private var projectPendingDeletionBinding: Binding<Bool> {
        Binding(
            get: { environment.board.projectPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    environment.board.projectPendingDeletion = nil
                }
            }
        )
    }

    private var taskPendingStopBinding: Binding<Bool> {
        Binding(
            get: { environment.board.taskPendingStop != nil },
            set: { isPresented in
                if !isPresented {
                    environment.board.taskPendingStop = nil
                }
            }
        )
    }

    private func deleteProjectPendingDeletion(_ plan: DeletionPlan) {
        environment.deletions.delete(plan)
        environment.board.projectPendingDeletion = nil
    }
}
