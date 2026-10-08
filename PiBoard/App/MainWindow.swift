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
                } else if let selectedProject {
                    BoardView(project: selectedProject)
                } else {
                    ContentUnavailableView("Select a Project", systemImage: "sidebar.left")
                }
            }
            // Attached to the always-present detail container: hosting it on BoardView let the
            // terminal swap remove the presenter mid-presentation and leave the window unhittable.
            .inspector(isPresented: inspectorBinding) {
                if showsBoard, let taskID = environment.board.selectedTaskID {
                    TaskInspectorView(taskID: taskID)
                        .inspectorColumnWidth(ideal: 300)
                } else {
                    ContentUnavailableView("No Task Selected", systemImage: "square.text.square")
                        .inspectorColumnWidth(ideal: 300)
                }
            }
        }
        .sheet(isPresented: pendingPreparationBinding, onDismiss: moveTerminalToOpenAfterPreparation) {
            if let taskID = environment.board.pendingPreparationTaskID {
                TaskPreparationView(taskID: taskID)
            }
        }
        .sheet(item: commitRequestBinding) { request in
            CommitSheet(request: request)
        }
        .toolbar {
            // One toolbar slot: the inspector on the board, the Changes panel on a terminal.
            ToolbarItem {
                if showsBoard {
                    Button("Inspector", systemImage: sidebarSystemImage) {
                        environment.board.isInspectorPresented.toggle()
                    }
                } else if environment.board.openTerminalTaskID != nil {
                    Button(TerminalChangesPanel.title, systemImage: sidebarSystemImage) {
                        environment.board.isChangesPanelPresented.toggle()
                    }
                    .help(TerminalChangesPanel.title)
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
        .frame(minWidth: 960, minHeight: 640)
    }

    private var showsBoard: Bool {
        environment.board.openTerminalTaskID == nil && selectedProject != nil
    }

    // The inspector only belongs to the board; hiding it elsewhere keeps the previous
    // behaviour where the terminal and empty states never showed it.
    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { showsBoard && environment.board.isInspectorPresented },
            set: { environment.board.isInspectorPresented = $0 }
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

    private func deleteProjectPendingDeletion(_ plan: DeletionPlan) {
        environment.deletions.delete(plan)
        environment.board.projectPendingDeletion = nil
    }
}
