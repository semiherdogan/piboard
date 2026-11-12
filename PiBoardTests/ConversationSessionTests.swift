import Foundation
import Observation
import Testing
@testable import PiBoard

@MainActor
struct ConversationSessionTests {
    private static let settleDelay: Duration = .milliseconds(50)
    private static let dialogTimeoutMs = 30
    private static let longDialogTimeoutMs = 60_000

    private final class Probe {
        var activities: [AgentActivity] = []
        var settledCount = 0
    }

    private func makeSession(_ harness: FakePiHarness) -> (ConversationSession, Probe) {
        let session = ConversationSession(driver: harness.driver, agentSettleDelay: Self.settleDelay)
        let probe = Probe()
        session.onAgentActivityChanged = { probe.activities.append($0) }
        session.onAgentSettled = { probe.settledCount += 1 }
        return (session, probe)
    }

    @Test func startWithAnInitialPromptBuildsAUserAndAnAssistantItem() async throws {
        let harness = try FakePiHarness()
        defer { harness.close() }
        let (session, probe) = makeSession(harness)

        session.start(initialPrompt: "hello")
        #expect(session.runtimeState == .running)
        await session.startupTask?.value
        #expect(await waitUntil { session.state.items.count == 2 && !session.state.isRunning })

        #expect(session.state.items[0].kind == .user(text: "hello", imageCount: 0))
        #expect(session.state.items[1].kind == .assistant(text: "d0 d1 d2 d3 d4 "))
        #expect(session.state.usage.total > 0)
        #expect(session.lastPromptDisposition == .started)
        #expect(session.lastError == nil)
        #expect(session.info?.sessionID == harness.sessionID)
        #expect(session.thinkingLevels == ["off", "low", "medium", "high"])
        #expect(session.commands.map(\.name) == ["fake-confirm"])
        #expect(session.state.thinkingLevel == "medium")

        #expect(await waitUntil { probe.settledCount >= 1 })
        try await Task.sleep(for: .milliseconds(200))
        #expect(probe.settledCount == 1)
        #expect(probe.activities == [.working, .idle])
        #expect(session.agentActivity == .idle)
    }

    @Test func resumeLoadsTheStoredHistory() async throws {
        let harness = try FakePiHarness(arguments: ["--fake-history", "2"])
        defer { harness.close() }
        let (session, _) = makeSession(harness)

        session.resume()
        await session.startupTask?.value

        #expect(session.state.items.map(\.kind) == [
            .user(text: "history question 0", imageCount: 0),
            .assistant(text: "history answer 0"),
            .user(text: "history question 1", imageCount: 0),
            .assistant(text: "history answer 1"),
        ])
        #expect(!session.state.isRunning)
        #expect(session.lastError == nil)
    }

    @Test func startShowsTheStoredActiveAgent() async throws {
        let harness = try FakePiHarness(arguments: ["--fake-active-agent", "architect"])
        defer { harness.close() }
        let (session, _) = makeSession(harness)

        session.start()
        await session.startupTask?.value

        #expect(session.state.activeAgentName == "architect")
        #expect(session.liveStatus.activeAgentName == "architect")
    }

    @Test func resumeShowsTheStoredActiveAgentAfterTheHistoryLoads() async throws {
        let harness = try FakePiHarness(arguments: ["--fake-history", "1", "--fake-active-agent", "architect"])
        defer { harness.close() }
        let (session, _) = makeSession(harness)

        session.resume()
        await session.startupTask?.value

        #expect(session.state.activeAgentName == "architect")
        #expect(session.state.items.count == 2)
    }

    @Test func aLiveEntryOverridesTheStoredActiveAgent() async throws {
        let harness = try FakePiHarness(arguments: ["--fake-active-agent", "architect"])
        defer { harness.close() }
        let (session, _) = makeSession(harness)
        session.start()
        await session.startupTask?.value

        await session.send("/fake-set-agent reviewer")

        #expect(await waitUntil { session.state.activeAgentName == "reviewer" })
    }

    @Test func aLiveEntryBeforeTheStoredEntriesArriveIsNotOverwritten() async {
        let driver = FakeConversationDriver()
        driver.storedEntries = [ConversationEntry(
            type: ConversationEntryType.custom,
            customType: ConversationCustomType.activeAgent,
            data: .object(["name": .string("architect")])
        )]
        let session = ConversationSession(driver: driver)
        driver.emit(.activeAgentChanged("reviewer"))

        await session.refreshInfo()

        #expect(session.state.activeAgentName == "reviewer")
    }

    @Test func aClearedStoredActiveAgentShowsNoName() async {
        let driver = FakeConversationDriver()
        driver.storedEntries = ["architect", nil].map { name in
            ConversationEntry(
                type: ConversationEntryType.custom,
                customType: ConversationCustomType.activeAgent,
                data: .object(["name": name.map(JSONValue.string) ?? .null])
            )
        }
        let session = ConversationSession(driver: driver)

        await session.refreshInfo()

        #expect(session.state.activeAgentName == nil)
    }

    @Test func aDialogNeedsInputUntilAnswered() async throws {
        let harness = try FakePiHarness()
        defer { harness.close() }
        let (session, probe) = makeSession(harness)
        session.start()
        await session.startupTask?.value

        let sending = Task { await session.send("/fake-confirm") }
        #expect(await waitUntil { session.state.pendingDialog != nil })
        #expect(session.agentActivity == .needsInput)

        session.answer(.confirmed(true))
        #expect(session.state.pendingDialog == nil)
        #expect(session.agentActivity == .idle)
        _ = await sending.value

        #expect(session.lastPromptDisposition == .handled)
        #expect(await waitUntil { session.state.items.contains { $0.kind == .notice(text: "confirmed: true") } })
        #expect(probe.activities.first == .needsInput)
    }

    private final class ChangeCounter: @unchecked Sendable {
        var count = 0
    }

    @Test func liveStatusObserversIgnoreDeltasButSeeRunChanges() {
        let driver = FakeConversationDriver()
        let session = ConversationSession(driver: driver)
        driver.emit(.messageStarted(role: .assistant))
        let counter = ChangeCounter()

        withObservationTracking { _ = session.liveStatus } onChange: { counter.count += 1 }
        driver.emit(.textDelta(index: 0, delta: "a"))
        #expect(counter.count == 0)

        driver.emit(.runStarted)
        #expect(counter.count == 1)
    }

    @Test func commandsAreRequestedOncePerSession() async {
        let driver = FakeConversationDriver()
        let session = ConversationSession(driver: driver)

        await session.refreshCommandsIfEmpty()
        await session.refreshCommandsIfEmpty()

        #expect(driver.commandsCallCount == 1)
    }

    @Test func aFailedCommandListIsSilent() async {
        struct ListFailure: Error {}
        let driver = FakeConversationDriver()
        driver.commandsError = ListFailure()
        let session = ConversationSession(driver: driver)

        await session.refreshCommandsIfEmpty()

        #expect(session.lastError == nil)
        #expect(session.commands.isEmpty)
    }

    @Test func dialogsAreAnsweredOneAtATime() {
        let driver = FakeConversationDriver()
        let session = ConversationSession(driver: driver)
        let first = ConversationDialog(id: "d1", method: .confirm)
        let second = ConversationDialog(id: "d2", method: .confirm)
        driver.emit(.dialogRequested(first))
        driver.emit(.dialogRequested(second))

        session.answer(.confirmed(true))

        #expect(session.state.pendingDialogs == [second])
        #expect(session.agentActivity == .needsInput)
        #expect(driver.answeredDialogIDs == ["d1"])
    }

    @Test func aDialogWithATimeoutDisappearsOnItsOwn() async {
        let driver = FakeConversationDriver()
        let session = ConversationSession(driver: driver)
        driver.emit(.dialogRequested(ConversationDialog(id: "d1", method: .confirm, timeoutMs: Self.dialogTimeoutMs)))
        driver.emit(.dialogRequested(ConversationDialog(id: "d2", method: .confirm)))

        #expect(await waitUntil { session.state.pendingDialogs.map(\.id) == ["d2"] })
        #expect(driver.answeredDialogIDs.isEmpty)
    }

    @Test func exitClearsEveryPendingDialog() {
        let driver = FakeConversationDriver()
        let session = ConversationSession(driver: driver)
        driver.emit(.dialogRequested(ConversationDialog(id: "d1", method: .confirm, timeoutMs: Self.longDialogTimeoutMs)))
        driver.emit(.dialogRequested(ConversationDialog(id: "d2", method: .confirm)))

        driver.exit(code: 0)

        #expect(session.state.pendingDialogs.isEmpty)
        #expect(session.agentActivity == .idle)
    }

    @Test func twoPromptsInARowBothReachTheDriverTheSecondAsFollowUp() async {
        let driver = FakeConversationDriver()
        driver.promptGate = true
        let session = ConversationSession(driver: driver)

        let first = Task { await session.send("one") }
        #expect(await waitUntil { driver.prompts.count == 1 })
        let second = Task { await session.send("two", whileRunning: .steer) }
        #expect(await waitUntil { driver.prompts.count == 2 })
        driver.releasePrompts()
        _ = await first.value
        _ = await second.value

        #expect(driver.prompts.map(\.text) == ["one", "two"])
        #expect(driver.prompts.map(\.whileRunning) == [nil, .steer])
    }

    @Test func aHandledPromptLeavesNoRunInFlight() async {
        let driver = FakeConversationDriver()
        driver.promptDisposition = .handled
        let session = ConversationSession(driver: driver)

        await session.send("/command")
        await session.send("next", whileRunning: .steer)

        #expect(driver.prompts.map(\.whileRunning) == [nil, nil])
    }

    @Test func aThrownPromptLeavesNoRunInFlight() async {
        let driver = FakeConversationDriver()
        driver.promptError = ConversationDriverError.notRunning
        let session = ConversationSession(driver: driver)

        let failed = await session.send("one")
        driver.promptError = nil
        let delivered = await session.send("two", whileRunning: .steer)

        #expect(!failed)
        #expect(delivered)
        #expect(session.lastError != nil)
        #expect(driver.prompts.map(\.whileRunning) == [nil, nil])
    }

    @Test func anOlderHandledPromptDoesNotClearANewerSendInFlight() async {
        let driver = FakeConversationDriver()
        driver.promptGate = true
        let session = ConversationSession(driver: driver)

        let first = Task { await session.send("a") }
        #expect(await waitUntil { driver.prompts.count == 1 })
        let second = Task { await session.send("b") }
        #expect(await waitUntil { driver.prompts.count == 2 })
        driver.releasePrompt(at: 0, with: .handled)
        _ = await first.value
        let third = Task { await session.send("c") }
        #expect(await waitUntil { driver.prompts.count == 3 })

        #expect(driver.prompts.map(\.whileRunning) == [nil, .followUp, .followUp])
        driver.releasePrompts()
        _ = await second.value
        _ = await third.value
    }

    @Test func aSettledRunCancelsTheTimeoutOfItsDialogs() async throws {
        let driver = FakeConversationDriver()
        let session = ConversationSession(driver: driver)
        driver.emit(.dialogRequested(ConversationDialog(id: "d1", method: .confirm, timeoutMs: Self.dialogTimeoutMs)))

        driver.emit(.runSettled(aborted: true))
        try await Task.sleep(for: .milliseconds(Self.dialogTimeoutMs * 3))

        #expect(session.state.pendingDialogs.isEmpty)
        #expect(session.agentActivity == .idle)
    }

    @Test func aKilledProcessShowsAsFailedNotFinished() async throws {
        let harness = try FakePiHarness()
        defer { harness.close() }
        let (session, _) = makeSession(harness)
        session.start()
        await session.startupTask?.value

        session.forceKill()

        #expect(await waitUntil { session.runtimeState.exitCode != nil })
        #expect(session.runtimeState == .exited(128 + SIGKILL))
    }

    @Test func exitMidRunFinishesStreamingItemsAndSetsTheRuntimeState() async throws {
        let harness = try FakePiHarness()
        defer { harness.close() }
        let (session, probe) = makeSession(harness)
        session.start()
        await session.startupTask?.value

        await session.send("/fake-crash")
        #expect(await waitUntil { session.runtimeState.exitCode != nil })

        #expect(session.runtimeState == .exited(3))
        #expect(!session.state.isRunning)
        #expect(!session.state.items.isEmpty)
        #expect(session.state.items.allSatisfy { !$0.isStreaming })
        #expect(session.agentActivity == .idle)
        #expect(probe.activities.last == .idle)
        try await Task.sleep(for: .milliseconds(200))
        #expect(probe.settledCount == 0)
        #expect(session.processID == nil)
    }

    @Test func stopShutsTheProcessDown() async throws {
        let harness = try FakePiHarness()
        defer { harness.close() }
        let (session, _) = makeSession(harness)
        session.start()
        await session.startupTask?.value

        session.stop()
        #expect(await waitUntil { session.runtimeState == .exited(0) })
    }

    @Test func aFailedCommandIsReportedNotThrown() async throws {
        let harness = try FakePiHarness(arguments: ["--fake-ignore", "get_commands"], commandTimeout: .milliseconds(200))
        defer { harness.close() }
        let (session, _) = makeSession(harness)

        session.start()
        await session.startupTask?.value

        #expect(session.lastError != nil)
        #expect(session.info != nil)
        #expect(session.thinkingLevels == ["off", "low", "medium", "high"])
    }
}
