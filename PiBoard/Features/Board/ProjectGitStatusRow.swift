import AppKit
import SwiftUI

private let commitSystemImage = "arrow.up.circle"

struct ProjectGitStatusRow: View {
    let project: Project
    @Environment(AppEnvironment.self) private var environment
    @State private var model: ProjectGitStatusModel?
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 16

    // A Pi exit is when the working tree most likely changed under us.
    private var activeTaskIDs: Set<UUID> {
        let processes = environment.processes
        return Set(environment.board.tasks(for: project.id).lazy.map(\.id).filter { taskID in
            let state = processes.runtimeState(for: taskID)
            return state == .running || state == .starting
        })
    }

    var body: some View {
        HStack(spacing: 10) {
            content
            if showsCommitButton {
                commitButton
            }
            if let remoteURL = model?.remoteURL {
                remoteButton(remoteURL)
            }
            if showsRefreshButton {
                refreshButton
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .frame(minHeight: rowHeight)
        .onAppear { refresh() }
        .onChange(of: project.id) { refresh() }
        .onChange(of: project.path) { refresh() }
        .onChange(of: activeTaskIDs) { refresh() }
        .onChange(of: environment.worktreeActions.revision) { refresh() }
        .onChange(of: environment.commits.revision) { refresh() }
        .onChange(of: environment.commits.changes.revision) { refresh() }
    }

    private var showsCommitButton: Bool {
        if case .ready(_, let changeCount) = model?.state ?? .idle {
            return changeCount > 0
        }
        return false
    }

    private var showsRefreshButton: Bool {
        switch model?.state ?? .idle {
        case .idle, .loading: false
        case .notRepository, .ready, .failed: true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model?.state ?? .idle {
        case .idle, .loading:
            EmptyView()
        case .notRepository:
            Label("Not a Git repository", systemImage: "questionmark.folder")
        case .ready(let branch, let changeCount):
            if let branch {
                Label(branch, systemImage: "arrow.triangle.branch")
            }
            if changeCount > 0 {
                Label(changeCount == 1 ? "1 change" : "\(changeCount) changes", systemImage: "pencil.circle")
                    .foregroundStyle(.orange)
            } else {
                Label("Clean", systemImage: "checkmark.circle")
            }
        case .failed(let message):
            Label("Git status unavailable", systemImage: "exclamationmark.triangle")
                .help(message)
        }
    }

    private var commitButton: some View {
        Button {
            environment.commits.begin(path: project.path, title: project.name)
        } label: {
            Image(systemName: commitSystemImage)
        }
        .buttonStyle(.plain)
        .help(CommitActions.menuTitle)
    }

    private func remoteButton(_ url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Image(systemName: "globe")
        }
        .buttonStyle(.plain)
        .help("Open \(url.host() ?? "remote") in Browser")
    }

    private var refreshButton: some View {
        Button {
            refresh(reloadRemote: true)
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.plain)
        .help("Refresh Git Status")
    }

    private func refresh(reloadRemote: Bool = false) {
        let model = model ?? ProjectGitStatusModel(git: environment.git)
        self.model = model
        model.refresh(path: project.path, reloadRemote: reloadRemote)
    }
}
