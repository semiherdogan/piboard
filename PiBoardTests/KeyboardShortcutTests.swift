import AppKit
import Foundation
import Testing
@testable import PiBoard

@MainActor
struct KeyboardShortcutTests {
    private static let quoteKeyCode: UInt16 = 42
    private static let otherKeyCode: UInt16 = 11

    private func event(
        _ flags: NSEvent.ModifierFlags,
        keyCode: UInt16 = quoteKeyCode,
        characters: String = "\""
    ) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    @Test func commandChordIsRecorded() throws {
        let shortcut = try #require(KeyboardShortcut(event: try event(.command)))
        #expect(shortcut.keyCode == Self.quoteKeyCode)
        #expect(shortcut.display.contains(ShortcutDisplay.commandSymbol))
    }

    @Test func chordWithoutCommandOptionOrControlIsRejected() throws {
        #expect(KeyboardShortcut(event: try event([])) == nil)
        #expect(KeyboardShortcut(event: try event(.shift)) == nil)
    }

    @Test func escapeIsReserved() throws {
        #expect(KeyboardShortcut(event: try event(.command, keyCode: KeyboardShortcut.escapeKeyCode)) == nil)
    }

    @Test func controlCharacterKeyFallsBackToKeyCode() throws {
        let shortcut = try #require(KeyboardShortcut(event: try event(.command, keyCode: 123, characters: "\u{F702}")))
        #expect(shortcut.display.hasSuffix("KEY 123"))
    }

    @Test func matchesSameKeyAndModifiers() throws {
        let shortcut = try #require(KeyboardShortcut(event: try event([.command, .shift])))
        #expect(shortcut.matches(try event([.command, .shift])))
        #expect(!shortcut.matches(try event(.command)))
        #expect(!shortcut.matches(try event([.command, .shift], keyCode: Self.otherKeyCode)))
    }

    @Test func matchIgnoresCapsLockAndFunctionFlags() throws {
        let shortcut = try #require(KeyboardShortcut(event: try event(.command)))
        #expect(shortcut.matches(try event([.command, .capsLock, .function])))
    }

    @Test func jsonRoundTrip() throws {
        let shortcut = try #require(KeyboardShortcut(event: try event(.command)))
        let original: [ShortcutAction: KeyboardShortcut] = [.toggleTerminal: shortcut]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([ShortcutAction: KeyboardShortcut].self, from: data)
        #expect(decoded == original)
    }
}
