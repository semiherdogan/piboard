import SwiftUI

private let emptyTitle = "No sessions yet"
private let emptyDescription = "New Session starts a prompt in the terminal or the chat."
private let emptySystemImage = "list.bullet"
private let branchSystemImage = "arrow.triangle.branch"
private let worktreeFallbackTitle = "Worktree"
private let openMenuTitle = "Open"
private let editMenuTitle = "Edit Task..."
private let duplicateMenuTitle = "Duplicate Task"
private let statusMenuTitle = "Status"
private let deleteMenuTitle = "Delete..."
private let commitSystemImage = "arrow.up.circle"
private let rowSpacing: CGFloat = 2
private let rowCornerRadius: CGFloat = 8
private let rowHorizontalPadding: CGFloat = 12
private let rowVerticalPadding: CGFloat = 8
private let rowContentSpacing: CGFloat = 10
private let titleDotSpacing: CGFloat = 6
private let agentSymbolWidth: CGFloat = 18
private let trailingMinSpacing: CGFloat = 8
private let listHorizontalPadding: CGFloat = 24
private let listBottomPadding: CGFloat = 24
private let selectedRowFillOpacity = 0.22

// Rows are lazy and reappear on scroll; this keeps one summary read per task and session.
private struct SummaryRefreshKey: Hashable {
    let taskID: UUID
    let sessionID: String
}

struct ProjectSessionListView: View {
    let project: Project
    @Environment(AppEnvironment.self) private var environment
    @State private var refreshedSummaries: Set<SummaryRefreshKey> = []

    private var tasks: [BoardTask] {
        let processes = environment.processes
        let projectTasks = environment.board.tasks.filter { $0.projectId == project.id }
        return SessionListOrdering.sorted(projectTasks) { taskID in
            processes.runtimeState(for: taskID).isActive
        }
    }

    var body: some View {
        let tasks = tasks
        if tasks.isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: emptySystemImage, description: Text(emptyDescription))
                .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: rowSpacing) {
                    ForEach(tasks) { task in
                        SessionRowView(task: task, refreshedSummaries: $refreshedSummaries)
                    }
                }
                .padding(.horizontal, listHorizontalPadding)
                .padding(.bottom, listBottomPadding)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct SessionRowView: View {
    let task: BoardTask
    @Binding var refreshedSummaries: Set<SummaryRefreshKey>
    @Environment(AppEnvironment.self) private var environment
    @State private var isHovered = false

    private var project: Project? {
        board.projects.first { $0.id == task.projectId }
    }

    private var board: BoardModel {
        environment.board
    }

    private var hasSession: Bool {
        task.sessionID != nil || environment.processes.session(for: task.id) != nil
    }

    private var agentActivity: AgentActivity? {
        environment.processes.agentActivity(for: task.id)
    }

    private var isRunning: Bool {
        let state = environment.processes.runtimeState(for: task.id)
        return state == .running || state == .starting
    }

    private var subtitle: String? {
        environment.sessionSummaries.summary(for: task.id)?.firstLineOfLastPrompt
            ?? SessionSummary.firstLine(of: task.prompt)
    }

    var body: some View {
        HStack(spacing: rowContentSpacing) {
            Image(systemName: task.agent.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: agentSymbolWidth)
            VStack(alignment: .leading, spacing: rowSpacing) {
                HStack(spacing: titleDotSpacing) {
                    statusDot
                    Text(task.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: trailingMinSpacing)
            trailing
        }
        .padding(.horizontal, rowHorizontalPadding)
        .padding(.vertical, rowVerticalPadding)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous))
        .contentShape(Rectangle())
        // The double tap is simultaneous so selecting on a single click never waits for the double-click window.
        .onTapGesture {
            board.selectedTaskID = task.id
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded { open() })
        .onHover { isHovered = $0 }
        .contextMenu { contextMenu }
        // Read once per task and session id for the list's lifetime; settles and exits refresh through AppEnvironment.
        .task(id: task.sessionID) {
            guard let sessionID = task.sessionID,
                  refreshedSummaries.insert(SummaryRefreshKey(taskID: task.id, sessionID: sessionID)).inserted else { return }
            environment.refreshSummary(taskID: task.id)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.sessionRow(task.id))
    }

    private var rowBackground: AnyShapeStyle {
        if board.selectedTaskID == task.id {
            return AnyShapeStyle(Color.accentColor.opacity(selectedRowFillOpacity))
        }
        return isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear)
    }

    // Same mapping as the sidebar's session rows: one dot, most urgent first, an empty slot keeps titles aligned.
    @ViewBuilder
    private var statusDot: some View {
        let processes = environment.processes
        if agentActivity == .needsInput {
            AgentStatusIndicator(kind: .needsInput)
        } else if agentActivity == .working || processes.runtimeState(for: task.id) == .starting {
            AgentStatusIndicator(kind: .working)
        } else if environment.attention.has(taskID: task.id) {
            AgentStatusIndicator(kind: .finished)
        } else if agentActivity == .idle {
            AgentStatusIndicator(kind: .idle)
        } else {
            AgentStatusIndicator(kind: .idle).hidden()
        }
    }

    private var trailing: some View {
        HStack(spacing: rowContentSpacing) {
            TimelineView(.everyMinute) { context in
                Text(CompactElapsedTime.string(from: task.updatedAt, to: context.date))
                    .monospacedDigit()
            }
            if hasSession {
                Image(systemName: task.interface.systemImage)
            }
            if task.runContext == .worktree {
                Label(task.worktreeBranch ?? worktreeFallbackTitle, systemImage: branchSystemImage)
                    .lineLimit(1)
            }
            Text(task.status.title)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func open() {
        board.selectedTaskID = task.id
        if hasSession {
            board.openTerminal(for: task.id)
        } else {
            board.prepareSession(taskID: task.id)
        }
    }

    // Mirrors TaskCardView's menu; the card's is tied to its drag and hover plumbing, so the shared items stay duplicated.
    @ViewBuilder
    private var contextMenu: some View {
        if hasSession {
            Button(openMenuTitle) {
                board.openTerminal(for: task.id)
            }
            if isRunning {
                Button(AgentStrings.stop(task.agent), role: .destructive) {
                    let processes = environment.processes
                    board.requestStop(taskID: task.id, agentActivity: agentActivity) { processes.stop(taskID: $0) }
                }
            }
        } else if task.status != .done {
            Button(AgentStrings.prepareAndStartNeutral) {
                board.prepareSession(taskID: task.id)
            }
        }
        Button(editMenuTitle) {
            board.selectedTaskID = task.id
            board.taskDetailID = task.id
        }
        Button(duplicateMenuTitle) {
            board.duplicateTask(task.id)
        }
        if SessionMigration.canMigrate(task) {
            let targets = SessionMigration.targets(for: task, enabled: environment.preferences.agentChoices)
            if !targets.isEmpty {
                Menu(AgentStrings.migrateMenuTitle) {
                    ForEach(targets, id: \.self) { kind in
                        Button(AgentStrings.migrateTo(kind, current: task.agent), systemImage: kind.systemImage) {
                            board.pendingMigration = BoardModel.PendingMigration(taskID: task.id, target: kind)
                        }
                    }
                }
            }
        }
        if let project {
            Divider()
            let target = ExternalAppActions.targetURL(for: task, project: project)
            OpenInPreferredAppsButtons(target: target)
            Button(CommitActions.menuTitle, systemImage: commitSystemImage) {
                environment.commits.begin(path: target, title: task.title)
            }
        }
        if task.worktreePath != nil {
            Button(WorktreeActions.removeMenuTitle) {
                environment.worktreeActions.requestRemoval(for: task.id)
            }
        }
        Divider()
        Menu(statusMenuTitle) {
            ForEach(TaskStatus.allCases, id: \.self) { status in
                Button(status.title) {
                    let processes = environment.processes
                    let targetCount = board.tasks(for: task.projectId, status: status).count
                    board.requestMove(taskID: task.id, to: status, at: targetCount) { taskID in
                        let state = processes.runtimeState(for: taskID)
                        return state == .running || state == .starting
                    }
                }
                .disabled(status == task.status)
            }
        }
        Divider()
        Button(deleteMenuTitle, role: .destructive) {
            board.taskPendingDeletion = task
        }
    }
}
