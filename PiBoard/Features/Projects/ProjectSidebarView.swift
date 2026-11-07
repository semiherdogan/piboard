import AppKit
import SwiftUI

private struct DroppedFolder: Identifiable {
    let id = UUID()
    let url: URL
}

private enum SidebarSelection: Hashable {
    case project(UUID)
    case session(UUID)
    // The "+N more" row under a project; it leads to the board, which lists everything.
    case more(UUID)
}

private let disclosureWidth: CGFloat = 12
private let projectRowSpacing: CGFloat = 8
private let sessionRowSpacing: CGFloat = 6
private let disclosureSystemImage = "chevron.right"
private let disclosureExpandedAngle: Double = 90
private let expandLabel = "Expand"
private let collapseLabel = "Collapse"
private let taskDetailsMenuTitle = TaskDetailCommand.title + "..."
private let moveToDoneMenuTitle = "Move to \(TaskStatus.done.title)"
private let titleTimeMinSpacing: CGFloat = 4

private func moreRowTitle(_ count: Int) -> String {
    "\(count) more"
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

    // An open terminal selects its session row, so a click on its project row is a real change
    // and shows the board. Re-clicking the selected project on the board may or may not reach the
    // setter; a change of project is handled by the model's didSet, so only a re-click calls
    // showBoard. No gesture competes with row selection.
    private var sidebarSelection: Binding<SidebarSelection?> {
        Binding(
            get: {
                if let taskID = board.openTerminalTaskID { return .session(taskID) }
                return board.selectedProjectID.map(SidebarSelection.project)
            },
            set: { selection in
                switch selection {
                case .project(let projectID):
                    let wasSelected = projectID == board.selectedProjectID
                    board.selectedProjectID = projectID
                    withAnimation(.snappy) {
                        board.expandSidebar(for: projectID)
                    }
                    if wasSelected {
                        board.showBoard(for: projectID)
                    }
                case .session(let taskID):
                    board.openSessionFromSidebar(taskID: taskID)
                case .more(let projectID):
                    board.selectedProjectID = projectID
                    board.showBoard(for: projectID)
                case nil:
                    board.selectedProjectID = nil
                }
            }
        )
    }

    private func sessionListing(for project: Project) -> SidebarSessions.Listing {
        let processes = environment.processes
        return SidebarSessions.listing(for: board.tasks(for: project.id)) { processes.session(for: $0) != nil }
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
                List(selection: sidebarSelection) {
                    Section("Projects") {
                        ForEach(board.projects) { project in
                            let listing = sessionListing(for: project)
                            let isExpanded = !board.collapsedProjectIDs.contains(project.id)
                            let shownSessions = isExpanded ? listing.visible : []
                            projectRow(project, listing: listing, shownTaskIDs: Set(shownSessions.map(\.id)))
                                .tag(SidebarSelection.project(project.id))
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
                            ForEach(shownSessions) { task in
                                sessionRow(task)
                                    .tag(SidebarSelection.session(task.id))
                                    .contextMenu { sessionMenu(task) }
                            }
                            if isExpanded, listing.hiddenCount > 0 {
                                moreRow(project, count: listing.hiddenCount)
                                    .tag(SidebarSelection.more(project.id))
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

    private func projectRow(_ project: Project, listing: SidebarSessions.Listing, shownTaskIDs: Set<UUID>) -> some View {
        // Tasks with a session row of their own show their dot there, not twice.
        let summarized = board.tasks(for: project.id).filter { !shownTaskIDs.contains($0.id) }
        return HStack(spacing: projectRowSpacing) {
            disclosure(for: project, hasSessions: !listing.visible.isEmpty)
            Image(systemName: "folder")
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                // With many projects the sidebar is the only place that answers "which one
                // should I look at": a green pulsing dot means an agent is working, grey means a
                // Pi is alive but waiting at the prompt, blue means one finished while you were away.
                HStack(spacing: 4) {
                    Text(ProjectPathService.abbreviated(project.path))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if hasRunningAgent(summarized) {
                        AgentStatusIndicator(kind: .working)
                    }
                    if hasAgentNeedingInput(summarized) {
                        AgentStatusIndicator(kind: .needsInput)
                    }
                    if environment.attention.hasAny(of: summarized.lazy.map(\.id)) {
                        AgentStatusIndicator(kind: .finished)
                    }
                    if hasIdleAgent(summarized) {
                        AgentStatusIndicator(kind: .idle)
                    }
                }
            }
            if !ProjectPathService.exists(project.path) {
                Spacer()
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.tertiary)
                    .help("Project folder not found")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.sidebarRow(project.id))
    }

    @ViewBuilder
    private func disclosure(for project: Project, hasSessions: Bool) -> some View {
        if hasSessions {
            let isExpanded = !board.collapsedProjectIDs.contains(project.id)
            Button {
                withAnimation(.snappy) {
                    board.toggleSidebarExpansion(for: project.id)
                }
            } label: {
                Image(systemName: disclosureSystemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? disclosureExpandedAngle : 0))
                    .frame(width: disclosureWidth)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? collapseLabel : expandLabel)
            .accessibilityIdentifier(AccessibilityID.sidebarDisclosure(project.id))
        } else {
            // Keeps project names aligned whether or not a row has a disclosure.
            Color.clear.frame(width: disclosureWidth, height: 1)
        }
    }

    // Indented so the session's dot sits under the project's folder icon.
    private var sessionIndent: CGFloat {
        disclosureWidth + projectRowSpacing
    }

    private func sessionRow(_ task: BoardTask) -> some View {
        HStack(spacing: sessionRowSpacing) {
            sessionDot(for: task)
            Text(task.title)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: titleTimeMinSpacing)
            TimelineView(.everyMinute) { context in
                Text(CompactElapsedTime.string(from: lastActivity(of: task), to: context.date))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, sessionIndent)
        // Only for sessions no card or terminal has read yet; settles and exits keep the rest current.
        .task(id: task.sessionID) {
            guard task.sessionID != nil, environment.sessionSummaries.summary(for: task.id) == nil,
                  let project = board.projects.first(where: { $0.id == task.projectId }) else { return }
            environment.sessionSummaries.refresh(task: task, project: project)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.sidebarSession(task.id))
    }

    // One dot per row, most urgent first; an empty slot keeps titles aligned.
    @ViewBuilder
    private func sessionDot(for task: BoardTask) -> some View {
        let processes = environment.processes
        let activity = processes.agentActivity(for: task.id)
        if activity == .needsInput {
            AgentStatusIndicator(kind: .needsInput)
        } else if activity == .working || processes.runtimeState(for: task.id) == .starting {
            AgentStatusIndicator(kind: .working)
        } else if environment.attention.has(taskID: task.id) {
            AgentStatusIndicator(kind: .finished)
        } else if activity == .idle {
            AgentStatusIndicator(kind: .idle)
        } else {
            AgentStatusIndicator(kind: .idle).hidden()
        }
    }

    private func lastActivity(of task: BoardTask) -> Date {
        environment.sessionSummaries.summary(for: task.id)?.lastActivity ?? task.updatedAt
    }

    @ViewBuilder
    private func sessionMenu(_ task: BoardTask) -> some View {
        Button(taskDetailsMenuTitle) {
            board.openTaskDetailsOnBoard(taskID: task.id)
        }
        if isTaskRunning(task.id) {
            Button(AgentStrings.stop(task.agent), role: .destructive) {
                let processes = environment.processes
                board.requestStop(taskID: task.id, agentActivity: processes.agentActivity(for: task.id)) { processes.stop(taskID: $0) }
            }
        } else {
            // Only offered once the agent stopped, so the move never needs the board's stop-and-move dialog.
            Button(moveToDoneMenuTitle) {
                let targetCount = board.tasks(for: task.projectId, status: .done).count
                board.requestMove(taskID: task.id, to: .done, at: targetCount, isRunning: isTaskRunning)
            }
        }
    }

    private func moreRow(_ project: Project, count: Int) -> some View {
        Text(moreRowTitle(count))
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, sessionIndent)
            .accessibilityIdentifier(AccessibilityID.sidebarMore(project.id))
    }

    private func isTaskRunning(_ taskID: UUID) -> Bool {
        let state = environment.processes.runtimeState(for: taskID)
        return state == .running || state == .starting
    }

    private func hasRunningAgent(_ tasks: [BoardTask]) -> Bool {
        let processes = environment.processes
        return tasks.contains {
            processes.agentActivity(for: $0.id) == .working || processes.runtimeState(for: $0.id) == .starting
        }
    }

    private func hasAgentNeedingInput(_ tasks: [BoardTask]) -> Bool {
        let processes = environment.processes
        return tasks.contains { processes.agentActivity(for: $0.id) == .needsInput }
    }

    private func hasIdleAgent(_ tasks: [BoardTask]) -> Bool {
        let processes = environment.processes
        return tasks.contains { processes.agentActivity(for: $0.id) == .idle }
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
