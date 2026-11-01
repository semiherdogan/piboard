import Foundation

/// Labels and timing for copying the agent's last reply from its session file.
enum LastReplyCopy {
    static let title = "Copy Last Reply"
    static let help = "Copy the agent's last reply without the terminal's line breaks"
    static let systemImage = "doc.on.doc"
    static let succeededSystemImage = "checkmark"
    static let failedSystemImage = "xmark"
    static let feedbackDuration: Duration = .seconds(1.5)
}
