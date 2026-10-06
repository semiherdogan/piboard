import AppKit
import SwiftUI

struct BoardView: View {
    let project: Project
    @Environment(AppEnvironment.self) private var environment
    @State private var showsNewTaskSheet = false
    @State private var showsFolderPicker = false

    private var pathExists: Bool {
        FileManager.default.fileExists(atPath: project.path.path)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if !pathExists {
                BannerView(
                    systemImage: "exclamationmark.triangle.fill",
                    title: "Project folder not found",
                    message: project.path.path,
                    actionTitle: "Locate Folder",
                    action: locateFolder
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
                    Button("Edit Project...") {}
                        .disabled(true)
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
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var abbreviatedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = project.path.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
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
            environment.board.updateProjectPath(project.id, path: url)
        }
    }
}
