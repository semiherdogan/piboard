import Testing
@testable import PiBoard
import Foundation

struct PiLaunchCommandTests {
    private let node = URL(fileURLWithPath: "/fake/node")
    private let piEntry = URL(fileURLWithPath: "/fake/cli.js")
    private let cwd = URL(fileURLWithPath: "/fake/cwd")

    @Test func newSessionWithNameAndPrompt() {
        let sessionID = UUID()
        let command = PiLaunchCommand.build(
            node: node,
            piEntry: piEntry,
            mode: .newSession(sessionID: sessionID, name: "PiBoard spike", initialPrompt: "hello"),
            cwd: cwd
        )

        #expect(command.executable == node)
        #expect(command.currentDirectory == cwd)
        #expect(command.arguments == [
            piEntry.path,
            "--session-id", sessionID.uuidString,
            "--name", "PiBoard spike",
            "hello"
        ])
    }

    @Test func newSessionWithoutNameOrPrompt() {
        let sessionID = UUID()
        let command = PiLaunchCommand.build(
            node: node,
            piEntry: piEntry,
            mode: .newSession(sessionID: sessionID, name: nil, initialPrompt: nil),
            cwd: cwd
        )

        #expect(command.arguments == [piEntry.path, "--session-id", sessionID.uuidString])
    }

    @Test func resume() {
        let sessionID = UUID()
        let command = PiLaunchCommand.build(
            node: node,
            piEntry: piEntry,
            mode: .resume(sessionID: sessionID),
            cwd: cwd
        )

        #expect(command.arguments == [piEntry.path, "--session", sessionID.uuidString])
    }

    @Test func headless() {
        let command = PiLaunchCommand.build(
            node: node,
            piEntry: piEntry,
            mode: .headless(prompt: "prompt text", systemPrompt: "sys"),
            cwd: cwd
        )

        #expect(command.arguments == [
            piEntry.path,
            "--print", "--no-tools", "--no-extensions", "--no-skills", "--no-context-files", "--no-session",
            "--thinking", "off",
            "--system-prompt", "sys",
            "prompt text",
        ])
    }

    @Test func promptWithSpacesAndQuotesIsSingleArgvElement() {
        let sessionID = UUID()
        let prompt = "say \"hello\" and list files"
        let command = PiLaunchCommand.build(
            node: node,
            piEntry: piEntry,
            mode: .newSession(sessionID: sessionID, name: nil, initialPrompt: prompt),
            cwd: cwd
        )

        #expect(command.arguments.last == prompt)
        #expect(command.arguments == [piEntry.path, "--session-id", sessionID.uuidString, prompt])
    }
}
