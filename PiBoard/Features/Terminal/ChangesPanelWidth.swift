import Foundation

/// Width of the terminal's Changes panel, remembered across launches.
enum ChangesPanelWidth {
    static let defaultValue: Double = 440
    static let minimum: Double = 320
    static let maximum: Double = 1200
    static let dividerWidth: Double = 1
    /// The hit area is wider than the drawn line so the divider is easy to grab.
    static let dividerHitWidth: Double = 8
    /// The terminal keeps at least this much; below it Pi's TUI is unreadable anyway.
    static let terminalMinimum: Double = 240

    /// The width the panel actually gets: the preference, unless the terminal would fall under
    /// its floor, in which case the panel gives way. It never goes under `minimum`, which the
    /// window's minimum size guarantees fits (960 minus the widest sidebar leaves room).
    static func effective(preferred: Double, available: Double) -> Double {
        let roomForPanel = available - terminalMinimum - dividerHitWidth
        let ceiling = max(minimum, roomForPanel)
        return min(preferred.clamped(to: minimum...maximum), ceiling)
    }
}
