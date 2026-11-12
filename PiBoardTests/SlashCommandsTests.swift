import Foundation
import Testing
@testable import PiBoard

struct SlashCommandsTests {
    private static let commands = [
        ConversationCommand(name: "review", description: "Review changes", source: "skill"),
        ConversationCommand(name: "preview", description: nil, source: "extension"),
        ConversationCommand(name: "Reset", description: "Start over", source: "prompt"),
        ConversationCommand(name: "skill:lint", description: nil, source: "skill"),
    ]

    @Test func fragmentIsTheNameBeingTyped() {
        #expect(SlashCommands.fragment(in: "/") == "")
        #expect(SlashCommands.fragment(in: "/rev") == "rev")
    }

    @Test func fragmentEndsAtWhitespaceOrWithoutASlash() {
        #expect(SlashCommands.fragment(in: "/review ") == nil)
        #expect(SlashCommands.fragment(in: "/review now") == nil)
        #expect(SlashCommands.fragment(in: "/a\nb") == nil)
        #expect(SlashCommands.fragment(in: "review") == nil)
        #expect(SlashCommands.fragment(in: " /review") == nil)
        #expect(SlashCommands.fragment(in: "") == nil)
    }

    @Test func emptyFragmentListsEveryCommandInOrder() {
        #expect(SlashCommands.matches(for: "", in: Self.commands) == Self.commands)
    }

    @Test func prefixMatchesComeBeforeContainingOnes() {
        let names = SlashCommands.matches(for: "rev", in: Self.commands).map(\.name)
        #expect(names == ["review", "preview"])
    }

    @Test func matchingIgnoresCase() {
        #expect(SlashCommands.matches(for: "RESET", in: Self.commands).map(\.name) == ["Reset"])
        #expect(SlashCommands.matches(for: "res", in: Self.commands).map(\.name) == ["Reset"])
    }

    @Test func aNameContainingTheFragmentMatches() {
        #expect(SlashCommands.matches(for: "lint", in: Self.commands).map(\.name) == ["skill:lint"])
    }

    @Test func noMatchIsEmpty() {
        #expect(SlashCommands.matches(for: "zzz", in: Self.commands).isEmpty)
    }

    @Test func insertionAddsTheSlashAndATrailingSpace() {
        #expect(SlashCommands.insertion(for: Self.commands[0]) == "/review ")
    }

    @Test func aListedCommandIsNotUnknown() {
        #expect(SlashCommands.unknownCommand(in: "/review the diff", known: Self.commands) == nil)
        #expect(SlashCommands.unknownCommand(in: "  /skill:lint\n", known: Self.commands) == nil)
    }

    @Test func anUnlistedWordIsUnknown() {
        #expect(SlashCommands.unknownCommand(in: "/settings", known: Self.commands) == "settings")
        #expect(SlashCommands.unknownCommand(in: "/settings now", known: Self.commands) == "settings")
        // Names are exact: the agent's own casing decides.
        #expect(SlashCommands.unknownCommand(in: "/reset", known: Self.commands) == "reset")
    }

    @Test func pathsAndPlainTextAreNotCommands() {
        #expect(SlashCommands.unknownCommand(in: "/usr/bin/env please", known: Self.commands) == nil)
        #expect(SlashCommands.unknownCommand(in: "/", known: Self.commands) == nil)
        #expect(SlashCommands.unknownCommand(in: "hello /settings", known: Self.commands) == nil)
    }

    @Test func returnSendsOnlyAnExactCommandName() {
        #expect(SlashCommands.isExact(fragment: "review", in: Self.commands))
        #expect(!SlashCommands.isExact(fragment: "rev", in: Self.commands))
        #expect(!SlashCommands.isExact(fragment: "Review", in: Self.commands))
        #expect(!SlashCommands.isExact(fragment: nil, in: Self.commands))
    }

    @Test func withoutAKnownListNothingCanBeJudged() {
        #expect(SlashCommands.unknownCommand(in: "/settings", known: []) == nil)
    }
}
