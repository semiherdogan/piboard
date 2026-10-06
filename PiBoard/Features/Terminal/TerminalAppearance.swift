import AppKit

/// Terminal colors and font applied to every `TerminalView`. A later milestone will replace
/// this constant with user-configurable terminal preferences.
/// `@unchecked`: `NSFont` isn't `Sendable`, but these values are immutable and only ever read.
struct TerminalAppearance: @unchecked Sendable {
    let foreground: NSColor
    let background: NSColor
    let cursor: NSColor
    let font: NSFont

    /// SwiftTerm's built-in default foreground is mid-gray, which collides visually with
    /// dim/gray text, so we override it with a near-white that reads distinctly from dim text.
    static let `default` = TerminalAppearance(
        foreground: NSColor(srgbRed: 0.92, green: 0.92, blue: 0.92, alpha: 1),
        background: NSColor(srgbRed: 0.10, green: 0.10, blue: 0.11, alpha: 1),
        cursor: NSColor(srgbRed: 0.92, green: 0.92, blue: 0.92, alpha: 1),
        font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    )
}
