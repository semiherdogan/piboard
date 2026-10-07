import SwiftUI

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
                    TerminalWorkspaceView(taskID: taskID, columnVisibility: $columnVisibility)
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
        .toolbar {
            ToolbarItem {
                Button("Inspector", systemImage: "sidebar.right") {
                    environment.board.isInspectorPresented.toggle()
                }
            }
        }
        .confirmationDialog(
            projectPendingDeletionTitle,
            isPresented: projectPendingDeletionBinding,
            presenting: environment.board.projectPendingDeletion
        ) { project in
            Button("Delete Project", role: .destructive) {
                deleteProjectPendingDeletion(project)
            }
            Button("Cancel", role: .cancel) {}
        } message: { project in
            Text("Removes the project and its \(environment.board.tasks(for: project.id).count) tasks from PiBoard. Files on disk, Git worktrees and Pi session history are not touched.")
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

    private func deleteProjectPendingDeletion(_ project: Project) {
        environment.board.deleteProject(id: project.id)
        environment.board.projectPendingDeletion = nil
    }
}
