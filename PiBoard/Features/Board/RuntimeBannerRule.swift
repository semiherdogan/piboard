import Foundation

/// Board-wide Pi banners only matter while Pi is one of the enabled agents.
enum RuntimeBannerRule {
    // A failed update keeps the active version, so only a missing runtime blocks the board.
    static func showsRuntimeBanner(isPiEnabled: Bool, status: AgentRuntimeStatus) -> Bool {
        isPiEnabled && status == .missing
    }

    static func showsTerminalProgressHint(isPiEnabled: Bool, isNeeded: Bool, isDismissed: Bool) -> Bool {
        isPiEnabled && isNeeded && !isDismissed
    }
}
