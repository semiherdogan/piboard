import AppKit
import SwiftUI

private struct DroppedFolder: Identifiable {
    let id = UUID()
    let url: URL
}

struct ProjectSidebarView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showsNewProjectSheet = false
    @State private var projectPendingEdit: Project?
    @State private var droppedFolder: DroppedFolder?
    @State private var isDropTargeted = false

    private var board: BoardModel {
        environment.board
    }

    var body: some View {
        @Bindable var board = board

        Group {
            if board.projects.isEmpty {
                ContentUnavailableView {
                    Label("No Projects", systemImage: "folder")
                } description: {
                    Text("Add a project folder to get started.")
                } actions: {
                    Button("Add Project") {
                        showsNewProjectSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List(selection: $board.selectedProjectID) {
                    Section("Projects") {
                        ForEach(board.projects) { project in
                            projectRow(project)
                                .tag(project.id)
                                .contextMenu {
                                    Button("Edit Project...") {
                                        projectPendingEdit = project
                                    }
                                    Button("Copy Path") {
                                        copyPath(project)
                                    }
                                    Button("Open in Finder") {
                                        openInFinder(project)
                                    }
                                    .disabled(!ProjectPathService.exists(project.path))
                                    Divider()
                                    Button("Delete Project...", role: .destructive) {
                                        board.projectPendingDeletion = project
                                    }
                                }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle("Projects")
        .safeAreaInset(edge: .bottom) {
            footer
        }
        .overlay {
            if isDropTargeted {
                dropHint
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls)
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.12)) {
                isDropTargeted = targeted
            }
        }
        .sheet(isPresented: $showsNewProjectSheet) {
            NewProjectSheet()
        }
        .sheet(item: $projectPendingEdit) { project in
            EditProjectSheet(project: project)
        }
        .sheet(item: $droppedFolder) { dropped in
            NewProjectSheet(initialFolder: dropped.url)
        }
    }

    private var dropHint: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: 2)
            .padding(4)
            .overlay {
                Label("Drop to add project", systemImage: "folder.badge.plus")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .allowsHitTesting(false)
    }

    private func handleDrop(_ urls: [URL]) -> Bool {
        guard droppedFolder == nil, let folder = urls.first(where: ProjectPathService.exists) else {
            return false
        }
        droppedFolder = DroppedFolder(url: folder)
        return true
    }

    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                Text(ProjectPathService.abbreviated(project.path))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !ProjectPathService.exists(project.path) {
                Spacer()
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.tertiary)
                    .help("Project folder not found")
            }
        }
        .padding(.vertical, 2)
    }

    private func copyPath(_ project: Project) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(project.path.path, forType: .string)
    }

    private func openInFinder(_ project: Project) {
        NSWorkspace.shared.activateFileViewerSelecting([project.path])
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Divider()
            HStack {
                Button(action: { showsNewProjectSheet = true }) {
                    Label("New Project", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                Spacer()
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
