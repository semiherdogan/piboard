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

// Holds the resolver outside SwiftUI state so a click does not re-render the sidebar.
@MainActor
private final class ProjectClickTracker {
    var resolver = ProjectClickResolver(navigationWindow: clickNavigationWindow)
}

// One click's tap and selection change land milliseconds apart; a double click's second click comes later.
private let clickNavigationWindow: TimeInterval = 0.1
private let groupGap: CGFloat = 6
private let moveUpMenuTitle = "Move Up"
private let moveDownMenuTitle = "Move Down"
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
    @State private var clickTracker = ProjectClickTracker()

    private static let errorDisplayDuration: Duration = .seconds(6)

    private var board: BoardModel {
        environment.board
    }

    // An open terminal selects its session row, so a click on its project row is a real change
    // and shows the board. Re-clicking the selected project on the board may or may not reach the
    // setter; the project name's tap gesture covers that click. A change of project is handled by
    // the model's didSet, so only a re-click calls showBoard.
    private var sidebarSelection: Binding<SidebarSelection?> {
        Binding(
            get: {
                if let taskID = board.openTerminalTaskID { return .session(taskID) }
                return board.selectedProjectID.map(SidebarSelection.project)
            },
            set: { selection in
                switch selection {
                case .project(let projectID):
                    let boardWasShown = board.isBoardShown(for: projectID)
                    let wasSelected = projectID == board.selectedProjectID
                    board.selectedProjectID = projectID
                    clickTracker.resolver.selectionChanged(to: projectID, boardWasShown: boardWasShown, at: Date())
                    if !boardWasShown {
                        withAnimation(.snappy) {
                            board.expandSidebar(for: projectID)
                        }
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
                let projectIDs = board.projects.map(\.id)
                let listings = Dictionary(uniqueKeysWithValues: board.projects.map { ($0.id, sessionListing(for: $0)) })
                let rows = SidebarOutline.rows(projectIDs: projectIDs, listings: listings, collapsed: board.collapsedProjectIDs)
                List(selection: sidebarSelection) {
                    Section("Projects") {
                        ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                            sidebarRow(row, listings: listings, endsGroup: endsGroup(at: index, in: rows))
                        }
                        // Only project rows can be picked up; their sessions follow them.
                        .onMove { source, destination in
                            guard source.count == 1, let first = source.first,
                                  let order = SidebarOutline.projectOrder(movingRowAt: first, to: destination, in: rows, projectIDs: projectIDs)
                            else { return }
                            board.reorderProjects(order)
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

    private func endsGroup(at index: Int, in rows: [SidebarOutline.Row]) -> Bool {
        guard rows.indices.contains(index + 1) else { return true }
        if case .project = rows[index + 1] { return true }
        return false
    }

    @ViewBuilder
    private func sidebarRow(_ row: SidebarOutline.Row, listings: [UUID: SidebarSessions.Listing], endsGroup: Bool) -> some View {
        switch row {
        case .project(let projectID):
            if let project = board.projects.first(where: { $0.id == projectID }), let listing = listings[projectID] {
                projectRow(project, listing: listing)
                    .tag(SidebarSelection.project(projectID))
                    .contextMenu { projectMenu(project) }
            }
        case .session(let taskID):
            if let task = board.tasks.first(where: { $0.id == taskID }) {
                sessionRow(task)
                    // Space only after an open group keeps folded projects tight.
                    .padding(.bottom, endsGroup ? groupGap : 0)
                    .tag(SidebarSelection.session(taskID))
                    .contextMenu { sessionMenu(task) }
                    .moveDisabled(true)
            }
        case .more(let projectID, let count):
            moreRow(projectID, count: count)
                .padding(.bottom, groupGap)
                .tag(SidebarSelection.more(projectID))
                .moveDisabled(true)
        }
    }

    @ViewBuilder
    private func projectMenu(_ project: Project) -> some View {
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
        let projectIDs = board.projects.map(\.id)
        Button(moveUpMenuTitle) {
            moveProject(project.id, by: -1)
        }
        .disabled(projectIDs.first == project.id)
        Button(moveDownMenuTitle) {
            moveProject(project.id, by: 1)
        }
        .disabled(projectIDs.last == project.id)
        Divider()
        Button("Delete Project...", role: .destructive) {
            board.projectPendingDeletion = project
        }
    }

    private func moveProject(_ projectID: UUID, by offset: Int) {
        guard let order = SidebarOutline.projectOrder(moving: projectID, by: offset, in: board.projects.map(\.id)) else { return }
        withAnimation(.snappy) {
            board.reorderProjects(order)
        }
    }

    private func projectRow(_ project: Project, listing: SidebarSessions.Listing) -> some View {
        // Tasks with a session row of their own show their dot there, not twice.
        let isExpanded = !board.collapsedProjectIDs.contains(project.id)
        let shownTaskIDs = isExpanded ? Set(listing.visible.map(\.id)) : []
        let summarized = board.tasks(for: project.id).filter { !shownTaskIDs.contains($0.id) }
        return HStack(spacing: projectRowSpacing) {
            disclosure(for: project, hasSessions: !listing.visible.isEmpty)
            // With many projects the sidebar is the only place that answers "which one should I
            // look at": green pulsing = working, grey = idle at the prompt, blue = finished while away.
            HStack(spacing: 4) {
                Text(project.name)
                    .lineLimit(1)
                Spacer(minLength: titleTimeMinSpacing)
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
                if !ProjectPathService.exists(project.path) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.tertiary)
                        .help("Project folder not found")
                }
            }
            .contentShape(Rectangle())
            // Next to the List's own selection, which may skip a click on the selected row.
            .simultaneousGesture(TapGesture().onEnded { handleProjectNameClick(project.id) })
        }
        .padding(.vertical, 2)
        .help(ProjectPathService.abbreviated(project.path))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.sidebarRow(project.id))
    }

    private func handleProjectNameClick(_ projectID: UUID) {
        guard clickTracker.resolver.tapped(projectID: projectID, boardShown: board.isBoardShown(for: projectID), at: Date()),
              let project = board.projects.first(where: { $0.id == projectID }),
              !sessionListing(for: project).visible.isEmpty else { return }
        withAnimation(.snappy) {
            board.toggleSidebarExpansion(for: projectID)
        }
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

    // Indented so the session's dot sits under the start of the project's name.
    private var sessionIndent: CGFloat {
        disclosureWidth + projectRowSpacing
    }

    private func sessionRow(_ task: BoardTask) -> some View {
        HStack(spacing: sessionRowSpacing) {
            sessionDot(for: task)
            // Quieter than the project names so the projects stay the structure of the list.
            Text(task.title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: titleTimeMinSpacing)
            TimelineView(.everyMinute) { context in
                Text(CompactElapsedTime.string(from: lastActivity(of: task), to: context.date))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .help(ClockTimestamp.full(lastActivity(of: task)))
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

    private func moreRow(_ projectID: UUID, count: Int) -> some View {
        Text(moreRowTitle(count))
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, sessionIndent)
            .accessibilityIdentifier(AccessibilityID.sidebarMore(projectID))
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
