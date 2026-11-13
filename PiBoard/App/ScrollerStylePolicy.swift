import Foundation

/// Makes every scroll view in the app use thin overlay scrollers, whatever the system setting.
enum ScrollerStylePolicy {
    static let defaultsKey = "AppleShowScrollBars"
    static let overlayValue = "WhenScrolling"

    // The per-app form of System Settings > Show scroll bars; AppKit reads it when it picks the process-wide scroller style.
    static func apply(to defaults: UserDefaults = .standard) {
        defaults.set(overlayValue, forKey: defaultsKey)
    }
}
