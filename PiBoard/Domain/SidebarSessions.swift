import Foundation

/// Which of a project's tasks the sidebar lists under it; the rest stay on the board.
enum SidebarSessions {
    static let visibleLimit = 5

    struct Listing {
        let visible: [BoardTask]
        let hiddenCount: Int
    }

    /// In Progress tasks with a session, in board order so rows do not jump while agents work.
    static func listing(for tasks: [BoardTask], hasLiveSession: (UUID) -> Bool, limit: Int = visibleLimit) -> Listing {
        let sessions = tasks
            .filter { $0.status == .inProgress && ($0.sessionID != nil || hasLiveSession($0.id)) }
            .sorted { $0.position < $1.position }
        return Listing(visible: Array(sessions.prefix(limit)), hiddenCount: max(0, sessions.count - limit))
    }
}

/// The sidebar as one flat list, so a project row can be dragged while its session rows follow it.
enum SidebarOutline {
    enum Row: Hashable {
        case project(UUID)
        case session(UUID)
        case more(projectID: UUID, count: Int)
    }

    static func rows(projectIDs: [UUID], listings: [UUID: SidebarSessions.Listing], collapsed: Set<UUID>) -> [Row] {
        projectIDs.flatMap { projectID -> [Row] in
            var rows: [Row] = [.project(projectID)]
            guard !collapsed.contains(projectID), let listing = listings[projectID] else { return rows }
            rows += listing.visible.map { .session($0.id) }
            if listing.hiddenCount > 0 { rows.append(.more(projectID: projectID, count: listing.hiddenCount)) }
            return rows
        }
    }

    /// The project order after a List move of one project row; the dropped project lands before the
    /// first other project at or below the drop point, so a drop among session rows ends their group.
    static func projectOrder(movingRowAt source: Int, to destination: Int, in rows: [Row], projectIDs: [UUID]) -> [UUID]? {
        guard rows.indices.contains(source), case .project(let moved) = rows[source] else { return nil }
        let target = rows[min(destination, rows.count)...].lazy.compactMap { row -> UUID? in
            if case .project(let id) = row, id != moved { return id }
            return nil
        }.first
        var order = projectIDs.filter { $0 != moved }
        order.insert(moved, at: target.flatMap(order.firstIndex(of:)) ?? order.endIndex)
        return order == projectIDs ? nil : order
    }

    /// Move Up and Move Down; nil when the project is already at that end.
    static func projectOrder(moving projectID: UUID, by offset: Int, in projectIDs: [UUID]) -> [UUID]? {
        guard let index = projectIDs.firstIndex(of: projectID) else { return nil }
        let target = index + offset
        guard projectIDs.indices.contains(target) else { return nil }
        var order = projectIDs
        order.swapAt(index, target)
        return order
    }
}

/// Tells a click on a project's name that only brought its board on screen from one that should
/// fold or unfold its sessions: a tap folds when the board was already showing as it landed.
/// The tap usually arrives just before the List's selection change; when the selection change
/// comes first, the tap that follows within `navigationWindow` belongs to it and does not fold.
struct ProjectClickResolver {
    private struct Event {
        let projectID: UUID
        let at: Date

        func isRecent(for projectID: UUID, at now: Date, within window: TimeInterval) -> Bool {
            self.projectID == projectID && now.timeIntervalSince(at) < window
        }
    }

    /// Shorter than the gap between the two clicks of a double click.
    let navigationWindow: TimeInterval
    private var navigation: Event?
    private var lastTap: Event?

    init(navigationWindow: TimeInterval) {
        self.navigationWindow = navigationWindow
    }

    mutating func selectionChanged(to projectID: UUID, boardWasShown: Bool, at now: Date) {
        // A tap that already landed for this click has decided; recording would swallow the next click.
        let tapCameFirst = lastTap?.isRecent(for: projectID, at: now, within: navigationWindow) == true
        navigation = boardWasShown || tapCameFirst ? nil : Event(projectID: projectID, at: now)
    }

    /// True when this tap should fold or unfold the project's sessions.
    mutating func tapped(projectID: UUID, boardShown: Bool, at now: Date) -> Bool {
        lastTap = Event(projectID: projectID, at: now)
        if navigation?.isRecent(for: projectID, at: now, within: navigationWindow) == true {
            navigation = nil
            return false
        }
        return boardShown
    }
}

/// "now", "4m", "3h", "2d": short enough for a sidebar row.
enum CompactElapsedTime {
    private static let nowLabel = "now"
    private static let minute = 60
    private static let hour = 3_600
    private static let day = 86_400

    static func string(from date: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<minute: return nowLabel
        case ..<hour: return "\(seconds / minute)m"
        case ..<day: return "\(seconds / hour)h"
        default: return "\(seconds / day)d"
        }
    }
}
