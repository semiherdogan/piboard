import Testing
@testable import PiBoard

// These pin the wording the monkey test and the docs rely on.
struct AgentStringsTests {
    @Test func piStringsAreUnchanged() {
        let kind = AgentKind.pi
        #expect(AgentStrings.stop(kind) == "Stop Pi")
        #expect(AgentStrings.resume(kind) == "Resume Pi")
        #expect(AgentStrings.start(kind) == "Start Pi")
        #expect(AgentStrings.prepareAndStart(kind) == "Prepare and Start Pi...")
        #expect(AgentStrings.exited(kind, code: 3) == "Pi exited (3)")
        #expect(AgentStrings.exited(kind, code: nil) == "Pi exited")
        #expect(AgentStrings.notRunning(kind) == "Pi is not running")
        #expect(AgentStrings.stopProcessQuestion(kind) == "Stop the Pi process for this task?")
        #expect(AgentStrings.stillWorkingQuestion(kind) == "Pi is still working on this task. Stop it?")
        #expect(AgentStrings.stillRunningMoveQuestion(kind) == "Pi is still running for this task. Stop it and move?")
        #expect(AgentStrings.sessionNotFound(kind) == "Pi session not found")
        #expect(AgentStrings.startNewSessionQuestion(kind) == "Start a new Pi session?")
        #expect(AgentStrings.runtimeNotInstalled(kind) == "Pi runtime is not installed")
        #expect(AgentStrings.stopIdleHelp(kind) == "Stop Pi (idle)")
        #expect(AgentStrings.alreadyRunningInTree(owner: "Task A", kind) == "Task A is already running Pi in this working tree.")
        #expect(AgentStrings.stopBeforeRemovingWorktree(kind) == "Stop the Pi session before removing the worktree.")
        #expect(AgentStrings.sessionFiles(count: 1, kind) == "Pi session file")
        #expect(AgentStrings.sessionFiles(count: 2, kind) == "Pi session files")
        #expect(AgentStrings.sessionFilesPlural(kind) == "Pi session files")
        #expect(AgentStrings.noSessionToResume(kind) == "The task has no Pi session to resume.")
        #expect(AgentStrings.willRunIn(path: "~/p", kind) == "Pi will run in ~/p.")
        #expect(AgentStrings.currentTreeBusy(kind) == "Another task is already running Pi in this working tree.")
        #expect(AgentStrings.sessionNotFoundOnDisk(kind) == "The Pi session for this task was not found on disk.")
    }
}
