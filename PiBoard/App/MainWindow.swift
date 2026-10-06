import SwiftUI

struct MainWindow: View {
    // Temporary spike UI (M0 step 2); delete alongside TerminalSpikeView once the real
    // terminal integration replaces it.
    @State private var showsTerminalSpike = false
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
            if showsTerminalSpike {
                TerminalSpikeView()
            } else if let taskID = environment.board.openTerminalTaskID {
                TerminalWorkspaceView(taskID: taskID, columnVisibility: $columnVisibility)
            } else if let selectedProject {
                BoardView(project: selectedProject)
                    .inspector(isPresented: Bindable(environment.board).isInspectorPresented) {
                        if let taskID = environment.board.selectedTaskID {
                            TaskInspectorView(taskID: taskID)
                                .inspectorColumnWidth(ideal: 300)
                        } else {
                            ContentUnavailableView("No Task Selected", systemImage: "square.text.square")
                                .inspectorColumnWidth(ideal: 300)
                        }
                    }
            } else {
                ContentUnavailableView("Select a Project", systemImage: "sidebar.left")
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Terminal Spike", systemImage: "terminal") {
                    showsTerminalSpike.toggle()
                }
            }
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
