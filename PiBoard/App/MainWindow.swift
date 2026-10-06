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
                        title: "Database unavailable",
                        message: startupError
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }

                if let taskID = environment.board.openTerminalTaskID {
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
