import AppKit
import SwiftUI

private struct DroppedFolder: Identifiable {
    let id = UUID()
    let url: URL
}

// Fresh id per failure so a repeated identical error restarts the auto-dismiss timer.
private struct SidebarError: Equatable {
    let id = UUID()
    let title: String
    let message: String
}

struct ProjectSidebarView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showsNewProjectSheet = false
    @State private var projectPendingEdit: Project?
    @State private var droppedFolder: DroppedFolder?
    @State private var isDropTargeted = false
    @State private var sidebarError: SidebarError?

    private static let errorDisplayDuration: Duration = .seconds(6)

    private var board: BoardModel {
        environment.board
    }

    // Re-clicking the selected project is a "show its board" request. The List may or may not
    // call the setter for an unchanged value; when it does, the terminal closes, and when it does
    // not, Back to Board still works. Either way no gesture competes with row selection.
    private var projectSelection: Binding<UUID?> {
        Binding(
            get: { board.selectedProjectID },
            set: { projectID in
                board.selectedProjectID = projectID
                if let projectID {
                    board.showBoard(for: projectID)
                }
            }
        )
    }

    var body: some View {
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
                List(selection: projectSelection) {
                    Section("Projects") {
                        ForEach(board.projects) { project in
                            projectRow(project)
                                .tag(project.id)
                                .contextMenu {
                                    OpenInPreferredAppsButtons(target: project.path)
                                    Divider()
                                    Button("Edit Project...") {
                                        projectPendingEdit = project
                                    }
                                    Button("Export Project...") {
                                        exportProject(project)
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
        .safeAreaInset(edge: .top) {
            if let sidebarError {
                BannerView(
                    systemImage: "exclamationmark.triangle.fill",
                    title: sidebarError.title,
                    message: sidebarError.message,
                    actionTitle: "Dismiss",
                    action: { self.sidebarError = nil }
                )
                .padding(8)
            }
        }
        .safeAreaInset(edge: .bottom) {
            footer
        }
        .task(id: sidebarError) {
            guard sidebarError != nil else { return }
            try? await Task.sleep(for: Self.errorDisplayDuration)
            guard !Task.isCancelled else { return }
            sidebarError = nil
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
        if let file = urls.first(where: ProjectExportPanels.isImportableFile) {
            importProject(from: file)
            return true
        }
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
                HStack(spacing: 6) {
                    // With many projects the sidebar is the only place that answers "which one
                    // should I look at", so both states are shown here.
                    if hasRunningAgent(project) {
                        AgentStatusIndicator(kind: .running)
                    }
                    if environment.attention.hasAny(of: board.tasks(for: project.id).lazy.map(\.id)) {
                        AgentStatusIndicator(kind: .finished)
                    }
                    Text(project.name)
                }
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

    private func hasRunningAgent(_ project: Project) -> Bool {
        let processes = environment.processes
        return board.tasks(for: project.id).contains { processes.runtimeState(for: $0.id).isActive }
    }

    private func copyPath(_ project: Project) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(project.path.path, forType: .string)
    }

    private func openInFinder(_ project: Project) {
        NSWorkspace.shared.activateFileViewerSelecting([project.path])
    }

    private func exportProject(_ project: Project) {
        do {
            try ProjectExportPanels.exportProject(project, from: board)
        } catch {
            sidebarError = SidebarError(title: "Export failed", message: error.localizedDescription)
        }
    }

    private func chooseAndImportProject() {
        guard let url = ProjectExportPanels.chooseImportFile() else { return }
        importProject(from: url)
    }

    private func importProject(from url: URL) {
        do {
            try ProjectExportPanels.importProject(contentsOf: url, into: board)
            sidebarError = nil
        } catch {
            sidebarError = SidebarError(title: "Import failed", message: error.localizedDescription)
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Divider()
            HStack {
                Menu {
                    Button("New Project...") {
                        showsNewProjectSheet = true
                    }
                    Button("Import Project...", action: chooseAndImportProject)
                } label: {
                    Label("New Project", systemImage: "plus.circle")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
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
