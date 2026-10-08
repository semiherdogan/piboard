import AppKit

/// Actions a user may bind a key to. One case per action; the raw value is the storage key
/// inside the shortcuts setting, so never rename a case's raw value.
enum ShortcutAction: String, CaseIterable, Codable, Sendable {
    case toggleTerminal = "toggle_terminal"

    var title: String {
        switch self {
        case .toggleTerminal: TerminalDrawerCommand.menuTitle
        }
    }
}

/// A physical key plus modifiers, so the binding survives keyboard layouts the way an editor's
/// "cmd+[IntlBackslash]" does. `display` is what the key produced when it was recorded, for the UI only.
struct KeyboardShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt16
    /// `NSEvent.ModifierFlags.deviceIndependentFlagsMask` subset: command, option, control, shift.
    let modifiers: UInt
    let display: String

    static let requiredModifiers: NSEvent.ModifierFlags = [.command, .option, .control]
    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    /// Reserved for cancelling a recording.
    static let escapeKeyCode: UInt16 = 53
    private static let unnamedKeyFormat = "key %d"

    init(keyCode: UInt16, modifiers: UInt, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }

    /// Nil when the chord has no command, option or control: a bare letter would steal typing.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(Self.relevantModifiers)
        guard !flags.isDisjoint(with: Self.requiredModifiers), event.keyCode != Self.escapeKeyCode else { return nil }
        keyCode = event.keyCode
        modifiers = flags.rawValue
        display = ShortcutDisplay.text(modifiers: flags, key: Self.keyName(for: event))
    }

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode && event.modifierFlags.intersection(Self.relevantModifiers) == modifierFlags
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection(Self.relevantModifiers)
    }

    /// Arrows and F-keys report control or private-use scalars, which render as nothing.
    private static func keyName(for event: NSEvent) -> String {
        let characters = event.charactersIgnoringModifiers ?? ""
        guard let first = characters.unicodeScalars.first,
              first.properties.generalCategory != .control,
              first.properties.generalCategory != .privateUse
        else {
            return String(format: unnamedKeyFormat, Int(event.keyCode))
        }
        return characters
    }
}

/// Builds the "⇧⌘\"" style text shown in Settings from a recorded event.
enum ShortcutDisplay {
    static let commandSymbol = "⌘"
    static let optionSymbol = "⌥"
    static let controlSymbol = "⌃"
    static let shiftSymbol = "⇧"

    static func text(modifiers: NSEvent.ModifierFlags, key: String) -> String {
        var result = ""
        if modifiers.contains(.control) { result += controlSymbol }
        if modifiers.contains(.option) { result += optionSymbol }
        if modifiers.contains(.shift) { result += shiftSymbol }
        if modifiers.contains(.command) { result += commandSymbol }
        return result + key.uppercased()
    }
}
