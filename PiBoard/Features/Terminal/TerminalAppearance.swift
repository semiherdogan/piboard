import AppKit

/// `NSFontManager` weight for a regular face (its scale runs 0 to 15).
private let regularFontManagerWeight = 5

/// Terminal colors and font applied to every `TerminalView`, derived from `AppPreferences`.
/// `@unchecked`: `NSFont` isn't `Sendable`, but these values are immutable and only ever read.
struct TerminalAppearance: @unchecked Sendable {
    let foreground: NSColor
    let background: NSColor
    let cursor: NSColor
    let font: NSFont
    let lineSpacing: CGFloat

    /// SwiftTerm's built-in default foreground is mid-gray, which collides visually with
    /// dim/gray text, so we override it with a near-white that reads distinctly from dim text.
    static let `default` = TerminalAppearance(
        foreground: NSColor(srgbRed: 0.92, green: 0.92, blue: 0.92, alpha: 1),
        background: NSColor(srgbRed: 0.10, green: 0.10, blue: 0.11, alpha: 1),
        cursor: NSColor(srgbRed: 0.92, green: 0.92, blue: 0.92, alpha: 1),
        font: NSFont.monospacedSystemFont(ofSize: TerminalFontChoice.defaultSize, weight: .regular),
        lineSpacing: TerminalLineHeight.defaultMultiplier
    )

    @MainActor
    static func make(from preferences: AppPreferences) -> TerminalAppearance {
        TerminalAppearance(
            foreground: Self.default.foreground,
            background: Self.default.background,
            cursor: Self.default.cursor,
            font: font(named: preferences.terminalFontName, size: preferences.terminalFontSize),
            lineSpacing: preferences.terminalLineHeightMultiplier
        )
    }

    /// The picker stores family names, which `NSFont(name:size:)` does not always resolve,
    /// so the family lookup is tried before falling back to the system monospaced font.
    @MainActor
    static func font(named name: String, size: Double) -> NSFont {
        let pointSize = CGFloat(size)
        if name != TerminalFontChoice.systemMonospaced {
            if let font = NSFont(name: name, size: pointSize) {
                return font
            }
            if let font = NSFontManager.shared.font(withFamily: name, traits: [], weight: regularFontManagerWeight, size: pointSize) {
                return font
            }
        }
        return NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
    }
}
