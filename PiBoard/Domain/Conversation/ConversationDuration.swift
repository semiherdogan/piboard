import Foundation

/// Compact elapsed time for the "Worked for" row: `12s`, `1m 18s`, `2h 3m`.
enum ConversationDuration {
    private static let secondsPerMinute = 60
    private static let secondsPerHour = 3600

    static func format(_ interval: TimeInterval) -> String {
        let total = max(Int(interval.rounded(.down)), 0)
        if total < secondsPerMinute {
            return "\(total)s"
        }
        if total < secondsPerHour {
            return "\(total / secondsPerMinute)m \(total % secondsPerMinute)s"
        }
        return "\(total / secondsPerHour)h \(total % secondsPerHour / secondsPerMinute)m"
    }
}
