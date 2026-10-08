import Foundation

/// Height of the board's terminal drawer, remembered across launches.
enum TerminalDrawerHeight {
    static let defaultValue: Double = 260
    static let minimum: Double = 140
    static let maximum: Double = 800
    static let dividerHeight: Double = 1
    /// The hit area is taller than the drawn line so the divider is easy to grab.
    static let dividerHitHeight: Double = 8
}
