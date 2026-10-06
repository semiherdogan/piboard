import AppKit
import SwiftTerm

enum TerminalFontChoice {
    /// Stored in place of a font name to mean "use the system monospaced font".
    static let systemMonospaced = ""
    static let defaultSize: Double = 13
    static let sizeRange: ClosedRange<Double> = 9...24
    static let sizeStep: Double = 1
}

enum TerminalLineHeight {
    static let defaultMultiplier: Double = 1.0
    static let range: ClosedRange<Double> = 0.9...1.6
    static let step: Double = 0.05
}

enum TerminalScrollback {
    static let defaultLines = 100_000
    static let choices = [10_000, 50_000, 100_000, 250_000]
}

enum TerminalOptionAsMeta {
    static let defaultValue = true
}

enum TerminalCursorShape: String, CaseIterable, Sendable {
    case block
    case underline
    case bar

    var title: String {
        switch self {
        case .block: "Block"
        case .underline: "Underline"
        case .bar: "Bar"
        }
    }
}

enum TerminalCursorStyleChoice: String, CaseIterable, Sendable {
    case blinkBlock
    case steadyBlock
    case blinkUnderline
    case steadyUnderline
    case blinkBar
    case steadyBar

    static let `default`: TerminalCursorStyleChoice = .blinkBlock

    init(shape: TerminalCursorShape, blinks: Bool) {
        switch shape {
        case .block: self = blinks ? .blinkBlock : .steadyBlock
        case .underline: self = blinks ? .blinkUnderline : .steadyUnderline
        case .bar: self = blinks ? .blinkBar : .steadyBar
        }
    }

    var shape: TerminalCursorShape {
        switch self {
        case .blinkBlock, .steadyBlock: .block
        case .blinkUnderline, .steadyUnderline: .underline
        case .blinkBar, .steadyBar: .bar
        }
    }

    var blinks: Bool {
        switch self {
        case .blinkBlock, .blinkUnderline, .blinkBar: true
        case .steadyBlock, .steadyUnderline, .steadyBar: false
        }
    }

    var swiftTermStyle: CursorStyle {
        switch self {
        case .blinkBlock: .blinkBlock
        case .steadyBlock: .steadyBlock
        case .blinkUnderline: .blinkUnderline
        case .steadyUnderline: .steadyUnderline
        case .blinkBar: .blinkBar
        case .steadyBar: .steadyBar
        }
    }
}

@MainActor
enum TerminalFontCatalog {
    /// Fixed-pitch font families, computed once because enumerating installed fonts is slow.
    static let monospacedFamilies: [String] = {
        let fontNames = NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? []
        let families = Set(fontNames.compactMap { NSFont(name: $0, size: TerminalFontChoice.defaultSize)?.familyName })
        return families.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }()
}
