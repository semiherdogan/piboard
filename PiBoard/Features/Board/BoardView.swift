import AppKit
import SwiftUI

struct BoardView: View {
    let project: Project
    @Environment(AppEnvironment.self) private var environment
    @State private var showsNewTaskSheet = false
    @State private var showsFolderPicker = false
    @State private var showsEditProjectSheet = false

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

            HStack(alignment: .top, spacing: 16) {
                ForEach(TaskStatus.allCases, id: \.self) { status in
                    BoardColumnView(project: project, status: status)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
