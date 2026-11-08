import AppKit
import Testing
@testable import PiBoard

struct TerminalEditingKeysTests {
    private let delete = TerminalEditingKeys.deleteKeyCode
    private let left = TerminalEditingKeys.leftArrowKeyCode
    private let right = TerminalEditingKeys.rightArrowKeyCode

    @Test func deletingMapsToControlWAndControlU() {
        #expect(TerminalEditingKeys.sequence(keyCode: delete, modifiers: .option) == [0x17])
        #expect(TerminalEditingKeys.sequence(keyCode: delete, modifiers: .command) == [0x15])
    }

    @Test func optionArrowsJumpByWord() {
        #expect(TerminalEditingKeys.sequence(keyCode: left, modifiers: .option) == [0x1B, UInt8(ascii: "b")])
        #expect(TerminalEditingKeys.sequence(keyCode: right, modifiers: .option) == [0x1B, UInt8(ascii: "f")])
    }

    @Test func commandArrowsGoToTheLineEnds() {
        #expect(TerminalEditingKeys.sequence(keyCode: left, modifiers: .command) == [0x01])
        #expect(TerminalEditingKeys.sequence(keyCode: right, modifiers: .command) == [0x05])
    }

    // Arrow key events carry .numericPad and .function; only the chord modifiers decide.
    @Test func deviceFlagsOnArrowKeysDoNotMatter() {
        #expect(TerminalEditingKeys.sequence(keyCode: left, modifiers: [.option, .numericPad, .function]) == [0x1B, UInt8(ascii: "b")])
    }

    @Test func otherCombinationsKeepTheirMeaning() {
        #expect(TerminalEditingKeys.sequence(keyCode: delete, modifiers: []) == nil)
        #expect(TerminalEditingKeys.sequence(keyCode: left, modifiers: []) == nil)
        #expect(TerminalEditingKeys.sequence(keyCode: left, modifiers: [.option, .shift]) == nil)
        #expect(TerminalEditingKeys.sequence(keyCode: left, modifiers: [.command, .option]) == nil)
        #expect(TerminalEditingKeys.sequence(keyCode: left, modifiers: .control) == nil)
    }
}
