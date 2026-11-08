import AppKit
import SwiftTerm

/// The text editing keys of macOS mapped to what shells and agent TUIs understand, as in iTerm's
/// "Natural Text Editing": control characters for deleting and line ends, Esc b / Esc f for words.
enum TerminalEditingKeys {
    // Virtual key codes from Carbon's Events.h; they name physical keys, so every layout agrees.
    static let deleteKeyCode: UInt16 = 51
    static let leftArrowKeyCode: UInt16 = 123
    static let rightArrowKeyCode: UInt16 = 124

    private static let escape: UInt8 = 0x1B
    private static let controlA: UInt8 = 0x01
    private static let controlE: UInt8 = 0x05
    private static let controlU: UInt8 = 0x15
    private static let controlW: UInt8 = 0x17
    private static let wordBackwardLetter = UInt8(ascii: "b")
    private static let wordForwardLetter = UInt8(ascii: "f")
    private static let chordModifiers: NSEvent.ModifierFlags = [.option, .command, .control, .shift]

    /// The bytes to send instead of the key, or nil when the key keeps its usual meaning.
    static func sequence(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> [UInt8]? {
        switch (modifiers.intersection(chordModifiers), keyCode) {
        case (.option, deleteKeyCode): [controlW]
        case (.command, deleteKeyCode): [controlU]
        case (.option, leftArrowKeyCode): [escape, wordBackwardLetter]
        case (.option, rightArrowKeyCode): [escape, wordForwardLetter]
        case (.command, leftArrowKeyCode): [controlA]
        case (.command, rightArrowKeyCode): [controlE]
        default: nil
        }
    }

    /// Sends the mapped bytes to the focused terminal; false leaves the event alone.
    @MainActor
    static func send(_ event: NSEvent) -> Bool {
        guard let terminal = event.window?.firstResponder as? TerminalView,
              let bytes = sequence(keyCode: event.keyCode, modifiers: event.modifierFlags)
        else { return false }
        // Like any typed key: the edited line no longer matches a highlighted selection.
        terminal.selectNone()
        terminal.send(bytes)
        return true
    }
}
