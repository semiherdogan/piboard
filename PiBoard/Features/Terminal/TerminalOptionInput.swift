import AppKit
import SwiftTerm

/// Keeps Option as Meta from swallowing characters that a keyboard layout types with Option, such as
/// `|`, `$`, `@` and `[` on Turkish or German layouts. US layouts produce symbols like `∫` there, so
/// their Option combinations stay Meta.
enum TerminalOptionInput {
    private static let printableASCII: ClosedRange<UInt32> = 0x21...0x7E
    private static let chordModifiers: NSEvent.ModifierFlags = [.option, .command, .control]

    /// True when Option alone turns the key into a plain ASCII character the key does not type without it.
    static func typesLayoutCharacter(characters: String?, charactersIgnoringModifiers: String?, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard modifiers.intersection(chordModifiers) == .option,
              let characters, characters != charactersIgnoringModifiers,
              characters.unicodeScalars.count == 1,
              let scalar = characters.unicodeScalars.first
        else { return false }
        return printableASCII.contains(scalar.value)
    }

    /// Types the character into the focused terminal with Meta off for this one key; false leaves the event alone.
    @MainActor
    static func typeLayoutCharacter(_ event: NSEvent) -> Bool {
        guard let terminal = event.window?.firstResponder as? TerminalView,
              terminal.optionAsMetaKey,
              typesLayoutCharacter(characters: event.characters, charactersIgnoringModifiers: event.charactersIgnoringModifiers, modifiers: event.modifierFlags)
        else { return false }
        terminal.optionAsMetaKey = false
        terminal.keyDown(with: event)
        terminal.optionAsMetaKey = true
        return true
    }
}
