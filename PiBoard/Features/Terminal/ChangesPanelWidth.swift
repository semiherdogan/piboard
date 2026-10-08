import Foundation

/// Width of the terminal's Changes panel, remembered across launches.
enum ChangesPanelWidth {
    static let defaultValue: Double = 440
    static let minimum: Double = 320
    static let maximum: Double = 1200
    static let dividerWidth: Double = 1
    /// The hit area is wider than the drawn line so the divider is easy to grab.
    static let dividerHitWidth: Double = 8
}
