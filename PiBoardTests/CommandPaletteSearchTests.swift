import Foundation
import Testing
@testable import PiBoard

struct CommandPaletteSearchTests {
    private let alpha = Project(id: UUID(), name: "Alpha", path: URL(fileURLWithPath: "/tmp/alpha"), defaultAgent: .default, createdAt: .now, updatedAt: .now)
    private let beta = Project(id: UUID(), name: "Beta", path: URL(fileURLWithPath: "/tmp/beta"), defaultAgent: .default, createdAt: .now, updatedAt: .now)

    private func makeTask(
        title: String,
        prompt: String = "",
        project: Project? = nil,
        status: TaskStatus = .backlog,
        sessionID: UUID? = nil
    ) -> BoardTask {
        BoardTask(
            id: UUID(),
            projectId: (project ?? alpha).id,
            agent: .default,
            title: title,
            prompt: prompt,
            status: status,
            position: 0,
            sessionID: sessionID?.uuidString,
            runContext: nil,
            worktreePath: nil,
            worktreeBranch: nil,
            createdAt: .now,
            updatedAt: .now
        )
    }

    @Test func blankQueryListsProjectsThenTasks() {
        let first = makeTask(title: "First")
        let second = makeTask(title: "Second", project: beta)

        let results = CommandPaletteSearch.results(query: "  ", projects: [alpha, beta], tasks: [first, second])

        #expect(results.map(\.id) == [alpha.id, beta.id, first.id, second.id])
    }

    @Test func prefixBeatsContains() {
        let contains = makeTask(title: "Fix login")
        let prefix = makeTask(title: "Login page")

        let results = CommandPaletteSearch.results(query: "login", projects: [alpha], tasks: [contains, prefix])

        #expect(results.map(\.id) == [prefix.id, contains.id])
    }

    @Test func diacriticsAndCaseAreIgnored() {
        let turkish = makeTask(title: "Ayr\u{E7}\u{131}\u{11F} fix")
        let other = makeTask(title: "Unrelated")

        let results = CommandPaletteSearch.results(query: "CIG", projects: [alpha], tasks: [turkish, other])

        #expect(results.map(\.id) == [turkish.id])
    }

    @Test func promptMatchesRankBelowTitleMatches() {
        let promptOnly = makeTask(title: "Unrelated", prompt: "Refactor the parser")
        let titleMatch = makeTask(title: "Parser cleanup")

        let results = CommandPaletteSearch.results(query: "parser", projects: [alpha], tasks: [promptOnly, titleMatch])

        #expect(results.map(\.id) == [titleMatch.id, promptOnly.id])
    }

    @Test func nonMatchingItemsAreDropped() {
        let task = makeTask(title: "Fix login")

        let results = CommandPaletteSearch.results(query: "zzz", projects: [alpha, beta], tasks: [task])

        #expect(results.isEmpty)
    }

    @Test func resultsAreCapped() {
        let tasks = (0..<(CommandPaletteSearch.maxResults + 5)).map { makeTask(title: "Task \($0)") }

        let results = CommandPaletteSearch.results(query: "", projects: [], tasks: tasks)

        #expect(results.count == CommandPaletteSearch.maxResults)
    }

    @Test func taskSubtitleNamesProjectAndStatus() throws {
        let task = makeTask(title: "Ship it", project: beta, status: .inProgress)

        let results = CommandPaletteSearch.results(query: "ship", projects: [alpha, beta], tasks: [task])

        let item = try #require(results.first)
        #expect(item.subtitle == "Beta / \(TaskStatus.inProgress.title)")
    }

    @Test func inProgressWithSessionIDGoesToTerminal() {
        let task = makeTask(title: "A", status: .inProgress, sessionID: UUID())
        #expect(CommandPaletteRouting.destination(for: task, hasLiveSession: false) == .terminal)
    }

    @Test func inProgressWithLiveSessionOnlyGoesToTerminal() {
        let task = makeTask(title: "A", status: .inProgress)
        #expect(CommandPaletteRouting.destination(for: task, hasLiveSession: true) == .terminal)
    }

    @Test func backlogWithSessionIDGoesToBoard() {
        let task = makeTask(title: "A", status: .backlog, sessionID: UUID())
        #expect(CommandPaletteRouting.destination(for: task, hasLiveSession: false) == .board)
    }

    @Test func inProgressWithoutSessionGoesToBoard() {
        let task = makeTask(title: "A", status: .inProgress)
        #expect(CommandPaletteRouting.destination(for: task, hasLiveSession: false) == .board)
    }
}
