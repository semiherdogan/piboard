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
