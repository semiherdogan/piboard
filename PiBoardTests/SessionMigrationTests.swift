import Foundation
import Testing
@testable import PiBoard

struct SessionMigrationTests {
    private let projectPath = URL(fileURLWithPath: "/tmp/migration-project")
    private let worktreePath = URL(fileURLWithPath: "/tmp/migration-worktree")

    @Test func cannotMigrateWithoutASession() {
        #expect(!SessionMigration.canMigrate(makeTask(sessionID: nil)))
    }

    @Test func canMigrateATaskWithASession() {
        #expect(SessionMigration.canMigrate(makeTask(sessionID: "s")))
    }

    @Test func inactiveSourceNeedsNoConfirmation() {
        #expect(SessionMigration.confirmation(isActive: false, activity: nil) == .none)
        #expect(SessionMigration.confirmation(isActive: false, activity: .working) == .none)
    }

    @Test func idleSourceStopsWithoutADialog() {
        #expect(SessionMigration.confirmation(isActive: true, activity: .idle) == .stopsRunning)
    }

    @Test func workingSourceAsksBeforeInterrupting() {
        #expect(SessionMigration.confirmation(isActive: true, activity: .working) == .interruptsWorking)
    }

    @Test func sourceNeedingInputAsksBeforeStopping() {
        #expect(SessionMigration.confirmation(isActive: true, activity: .needsInput) == .interruptsWorking)
    }

    @Test func sourceWithoutAnActivitySignalAsksBeforeStopping() {
        #expect(SessionMigration.confirmation(isActive: true, activity: nil) == .interruptsWorking)
    }

    @Test func editedSummaryKeepsTheTranscriptAfterTheStop() {
        let result = SessionMigration.transcriptAfterStop(current: transcript("old"), reread: transcript("new"), isEdited: true)
        #expect(result == nil)
    }

    @Test func failedRereadKeepsTheTranscriptAfterTheStop() {
        let result = SessionMigration.transcriptAfterStop(current: transcript("old"), reread: nil, isEdited: false)
        #expect(result == nil)
    }

    @Test func successfulRereadReplacesTheTranscriptAfterTheStop() {
        let result = SessionMigration.transcriptAfterStop(current: transcript("old"), reread: transcript("new"), isEdited: false)
        #expect(result == transcript("new"))
    }

    @Test func failureMessageAddsTheResumeNoteOnlyWhenTheSourceWasStopped() {
        #expect(SessionMigration.failureMessage("boom", stoppedSource: false) == "boom")
        #expect(SessionMigration.failureMessage("boom", stoppedSource: true) == "boom" + SessionMigration.previousSessionStoppedNote)
    }

    private func transcript(_ text: String) -> SessionTranscript {
        var transcript = SessionTranscript()
        transcript.messages = [.init(role: .user, text: text, timestamp: nil)]
        return transcript
    }

    @Test func targetsKeepTheEnabledOrderAndIncludeTheCurrentAgent() {
        let task = makeTask(sessionID: "s", agent: .opencode)
        let targets = SessionMigration.targets(for: task, enabled: [.claudeCode, .opencode, .pi])
        #expect(targets == [.claudeCode, .opencode, .pi])
    }

    @Test func targetsWithOneEnabledAgentOfferAFreshSessionOfIt() {
        let task = makeTask(sessionID: "s", agent: .pi)
        #expect(SessionMigration.targets(for: task, enabled: [.pi]) == [.pi])
    }

    @Test func launchDirectoryPicksTheWorktreeForAWorktreeTask() {
        let task = makeTask(sessionID: "s", runContext: .worktree, worktreePath: worktreePath)
        let directory = SessionMigration.launchDirectory(task: task, project: makeProject())
        #expect(directory.context == .worktree)
        #expect(directory.cwd == worktreePath)
    }

    @Test func launchDirectoryFallsBackToTheProjectWithoutAWorktreePath() {
        let task = makeTask(sessionID: "s", runContext: .worktree, worktreePath: nil)
        let directory = SessionMigration.launchDirectory(task: task, project: makeProject())
        #expect(directory.context == .current)
        #expect(directory.cwd == projectPath)
    }

    @Test func launchDirectoryIgnoresAWorktreePathInTheCurrentTree() {
        let task = makeTask(sessionID: "s", runContext: .current, worktreePath: worktreePath)
        let directory = SessionMigration.launchDirectory(task: task, project: makeProject())
        #expect(directory.context == .current)
        #expect(directory.cwd == projectPath)
    }

    private func makeProject() -> Project {
        Project(id: UUID(), name: "P", path: projectPath, defaultAgent: .default, createdAt: Date(), updatedAt: Date())
    }

    private func makeTask(
        sessionID: String?,
        agent: AgentKind = .default,
        runContext: RunContext? = nil,
        worktreePath: URL? = nil
    ) -> BoardTask {
        BoardTask(
            id: UUID(),
            projectId: UUID(),
            agent: agent,
            title: "Task",
            prompt: "",
            status: .inProgress,
            position: 0,
            sessionID: sessionID,
            runContext: runContext,
            worktreePath: worktreePath,
            worktreeBranch: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
