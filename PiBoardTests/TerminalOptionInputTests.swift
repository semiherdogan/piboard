import AppKit
import Testing
@testable import PiBoard

struct TerminalOptionInputTests {
    // Turkish Q: Option+4 is $, Option+- is |, Option+Q is @, Option+8 is [.
    @Test(arguments: [("$", "4"), ("|", "-"), ("@", "q"), ("[", "8"), ("\\", "*")])
    func optionCharactersOfALayoutAreTyped(characters: String, plain: String) {
        #expect(TerminalOptionInput.typesLayoutCharacter(characters: characters, charactersIgnoringModifiers: plain, modifiers: .option))
    }

    @Test func usOptionSymbolsStayMeta() {
        // US Option+B types ∫, which nobody means in a terminal; Meta+B is word back.
        #expect(TerminalOptionInput.typesLayoutCharacter(characters: "∫", charactersIgnoringModifiers: "b", modifiers: .option) == false)
    }

    @Test func optionEnterAndDeadKeysStayMeta() {
        #expect(TerminalOptionInput.typesLayoutCharacter(characters: "\r", charactersIgnoringModifiers: "\r", modifiers: .option) == false)
        #expect(TerminalOptionInput.typesLayoutCharacter(characters: "", charactersIgnoringModifiers: "e", modifiers: .option) == false)
    }

    @Test func otherChordsAreLeftAlone() {
        #expect(TerminalOptionInput.typesLayoutCharacter(characters: "$", charactersIgnoringModifiers: "4", modifiers: []) == false)
        #expect(TerminalOptionInput.typesLayoutCharacter(characters: "$", charactersIgnoringModifiers: "4", modifiers: [.option, .command]) == false)
        #expect(TerminalOptionInput.typesLayoutCharacter(characters: "$", charactersIgnoringModifiers: "4", modifiers: [.option, .control]) == false)
    }

    @Test func shiftDoesNotMatter() {
        #expect(TerminalOptionInput.typesLayoutCharacter(characters: "{", charactersIgnoringModifiers: "*", modifiers: [.option, .shift]))
    }

    @Test func aKeyThatTypesTheSameWithOptionStaysMeta() {
        #expect(TerminalOptionInput.typesLayoutCharacter(characters: "a", charactersIgnoringModifiers: "a", modifiers: .option) == false)
    }
}
