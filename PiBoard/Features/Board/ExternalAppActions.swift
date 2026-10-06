import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ExternalAppActions {
    static let openInMenuTitle = "Open In"
    static let openInMenuSystemImage = "arrow.up.forward.app"
    static let notInstalledSuffix = " (not installed)"

    // LaunchServices lookups are memoized so menus and toolbars never query them while rendering.
    private(set) var installedApps: Set<ExternalApp> = []
    // Exposed so tests can await completion.
    private(set) var openTask: Task<Void, Never>?

    private let service: ExternalAppServicing
    private let board: BoardModel

    init(service: ExternalAppServicing, board: BoardModel) {
        self.service = service
        self.board = board
        refresh()
    }

    static func openTitle(_ app: ExternalApp) -> String {
        "Open in \(app.title)"
    }

    /// The worktree when the task runs in one that still exists, otherwise the project folder.
    static func targetURL(for task: BoardTask, project: Project) -> URL {
        if task.runContext == .worktree, let worktreePath = task.worktreePath, ProjectPathService.exists(worktreePath) {
            return worktreePath
        }
        return project.path
    }

    func refresh() {
        installedApps = Set(ExternalApp.allCases.filter(service.isAvailable))
    }

    func isInstalled(_ app: ExternalApp) -> Bool {
        installedApps.contains(app)
    }

    func open(_ target: URL, in app: ExternalApp) {
        let service = service
        openTask = Task { [weak self] in
            do {
                try await service.open(target, in: app)
            } catch {
                self?.board.lastError = "Could not open in \(app.title): \(error.localizedDescription)"
            }
        }
    }
}

/// "Open in <editor>" and "Open in <terminal>" for the user's preferred apps.
struct OpenInPreferredAppsButtons: View {
    let target: URL
    var includesFinder = false
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let preferences = environment.preferences
        button(for: preferences.preferredEditor)
        button(for: preferences.preferredTerminal)
        if includesFinder {
            button(for: .finder)
        }
    }

    private func button(for app: ExternalApp) -> some View {
        let actions = environment.externalApps
        return Button(ExternalAppActions.openTitle(app), systemImage: app.systemImage) {
            actions.open(target, in: app)
        }
        .disabled(!actions.isInstalled(app) || !ProjectPathService.exists(target))
    }
}

/// Every installed app, grouped editors, terminals, then Finder.
struct OpenInAllAppsMenuItems: View {
    let target: URL
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let actions = environment.externalApps
        let groups = [ExternalApp.editors, ExternalApp.terminals, [ExternalApp.finder]]
            .map { $0.filter(actions.isInstalled) }
            .filter { !$0.isEmpty }
        ForEach(groups.indices, id: \.self) { index in
            if index > 0 {
                Divider()
            }
            ForEach(groups[index], id: \.self) { app in
                Button(app.title, systemImage: app.systemImage) {
                    actions.open(target, in: app)
                }
            }
        }
    }
}
