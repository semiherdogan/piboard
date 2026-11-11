import Foundation
import Testing
@testable import PiBoard

@MainActor
struct PiRPCDriverTests {
    private static let sigkillExitCode: Int32 = 128 + SIGKILL
    private static let stderrCrashExitCode: Int32 = 1
    private static let stderrLastLine = "fake trace end"
    // Well under the fake's 6 s grandchild lifetime, so only the drain timeout can have ended the wait.
    private static let holdStdoutExitLimit: Duration = .seconds(4)

    @Test func startsAndAnswersState() async throws {
        let harness = try FakePiHarness()
        defer { harness.close() }
        try harness.driver.start()

        let info = try await harness.driver.state()
        #expect(info.sessionID == harness.sessionID)
        #expect(info.modelID == "fake-model")
        #expect(info.thinkingLevel == "medium")
        #expect(harness.driver.processID != nil)
    }

    @Test func promptDeliversEventsInOrderEndingWithSettle() async throws {
        let harness = try FakePiHarness()
        defer { harness.close() }
        let recorder = DriverRecorder(harness.driver)
        try harness.driver.start()

        let disposition = try await harness.driver.prompt("hello", images: [], whileRunning: nil)
        #expect(disposition == .started)
        #expect(await waitUntil { recorder.events.last == .runSettled(aborted: false) })

        let events = recorder.events
        let started = try #require(events.firstIndex(of: .runStarted))
        let turn = try #require(events.firstIndex(of: .turnStarted))
        let userEnd = try #require(events.firstIndex { if case .messageEnded(let m) = $0 { m.role == .user } else { false } })
        let firstDelta = try #require(events.firstIndex { if case .textDelta = $0 { true } else { false } })
        let textEnd = try #require(events.firstIndex { if case .textEnded = $0 { true } else { false } })
        let assistantEnd = try #require(events.firstIndex { if case .messageEnded(let m) = $0 { m.role == .assistant } else { false } })
        let turnEnd = try #require(events.firstIndex(of: .turnEnded))
        #expect(started < turn)
        #expect(turn < userEnd)
        #expect(userEnd < firstDelta)
        #expect(firstDelta < textEnd)
        #expect(textEnd < assistantEnd)
        #expect(assistantEnd < turnEnd)
        #expect(recorder.textDeltas == ["d0 ", "d1 ", "d2 ", "d3 ", "d4 "])
        #expect(events.filter { $0 == .runSettled(aborted: false) }.count == 1)
    }

    @Test func abortMidStreamSettlesBeforeTheCallReturns() async throws {
        let harness = try FakePiHarness(arguments: ["--fake-deltas", "300"])
        defer { harness.close() }
        let recorder = DriverRecorder(harness.driver)
        try harness.driver.start()

        _ = try await harness.driver.prompt("long", images: [], whileRunning: nil)
        #expect(await waitUntil { recorder.textDeltas.count >= 2 })
        try await harness.driver.abort()

        #expect(recorder.events.last == .runSettled(aborted: true))
        let aborted = recorder.events.contains { event in
            if case .messageEnded(let message) = event { return message.stopReason == "aborted" }
            return false
        }
        #expect(aborted)
        #expect(recorder.textDeltas.count < 300)
    }

    @Test func confirmDialogBlocksThePromptUntilAnswered() async throws {
        let harness = try FakePiHarness()
        defer { harness.close() }
        let recorder = DriverRecorder(harness.driver)
        try harness.driver.start()

        let driver = harness.driver
        let prompt = Task { try await driver.prompt("/fake-confirm", images: [], whileRunning: nil) }
        #expect(await waitUntil { recorder.pendingDialogID != nil })
        let dialogID = try #require(recorder.pendingDialogID)
        let dialog = recorder.events.compactMap { event -> ConversationDialog? in
            if case .dialogRequested(let dialog) = event { return dialog }
            return nil
        }.first
        #expect(dialog?.method == .confirm)

        try harness.driver.answer(dialogID: dialogID, with: .confirmed(true))
        #expect(try await prompt.value == .handled)
        #expect(recorder.events.contains(.notified(message: "confirmed: true")))
    }

    @Test func shutdownClosesStdinAndReportsCleanExit() async throws {
        let harness = try FakePiHarness()
        defer { harness.close() }
        let recorder = DriverRecorder(harness.driver)
        try harness.driver.start()
        _ = try await harness.driver.state()

        let began = ContinuousClock.now
        harness.driver.shutdown()
        #expect(await waitUntil { recorder.didExit })
        #expect(recorder.exitCode == 0)
        #expect(ContinuousClock.now - began < .seconds(ProcessQuitPolicy.gracePeriod))
        #expect(harness.driver.processID == nil)
    }

    @Test func deathBySignalReportsTheShellStyleExitCode() async throws {
        let harness = try FakePiHarness()
        defer { harness.close() }
        let recorder = DriverRecorder(harness.driver)
        try harness.driver.start()
        _ = try await harness.driver.state()

        harness.driver.forceKill()
        #expect(await waitUntil { recorder.didExit })
        #expect(recorder.exitCode == Self.sigkillExitCode)
    }

    @Test func stderrOutputIsLoggedNotTreatedAsAnError() async throws {
        let harness = try FakePiHarness()
        defer { harness.close() }
        try harness.driver.start()

        _ = try await harness.driver.state()
        #expect(await waitUntil { !harness.driver.lastStderrLines.isEmpty })
        #expect(harness.driver.lastStderrLines.first?.hasPrefix("Warning:") == true)
    }

    @Test func theEndOfACrashTraceReachesTheStderrTail() async throws {
        let harness = try FakePiHarness()
        defer { harness.close() }
        let recorder = DriverRecorder(harness.driver)
        try harness.driver.start()
        _ = try await harness.driver.state()

        let driver = harness.driver
        let crashing = Task { await thrownError { _ = try await driver.prompt("/fake-stderr-crash", images: [], whileRunning: nil) } }
        #expect(await waitUntil { recorder.didExit })
        _ = await crashing.value

        #expect(recorder.exitCode == Self.stderrCrashExitCode)
        #expect(driver.lastStderrLines.last == Self.stderrLastLine)
    }

    @Test func aGrandchildHoldingStdoutOpenDoesNotBlockTheExit() async throws {
        let harness = try FakePiHarness(arguments: ["--fake-hold-stdout"])
        defer { harness.close() }
        let recorder = DriverRecorder(harness.driver)
        try harness.driver.start()
        _ = try await harness.driver.state()

        harness.driver.shutdown()
        #expect(await waitUntil(timeout: Self.holdStdoutExitLimit) { recorder.didExit })
        #expect(recorder.exitCode == 0)
    }

    @Test func aCommandAfterExitThrowsNotRunning() async throws {
        let harness = try FakePiHarness()
        defer { harness.close() }
        let recorder = DriverRecorder(harness.driver)
        try harness.driver.start()
        _ = try await harness.driver.state()
        harness.driver.shutdown()
        #expect(await waitUntil { recorder.didExit })

        let driver = harness.driver
        #expect(await thrownError { _ = try await driver.state() } as? ConversationDriverError == .notRunning)
        #expect(throws: ConversationDriverError.notRunning) {
            try driver.answer(dialogID: "x", with: .cancelled)
        }
    }

    @Test func aCommandThePiNeverAnswersTimesOut() async throws {
        let harness = try FakePiHarness(arguments: ["--fake-ignore", "get_commands"], commandTimeout: .milliseconds(300))
        defer { harness.close() }
        try harness.driver.start()

        let driver = harness.driver
        #expect(await thrownError { _ = try await driver.commands() } as? ConversationDriverError == .timeout("get_commands"))
        // The driver stays usable after a timeout.
        #expect(try await driver.state().sessionID == harness.sessionID)
    }

    @Test func exitFailsACommandThatIsStillWaiting() async throws {
        let harness = try FakePiHarness(arguments: ["--fake-ignore", "get_commands"])
        defer { harness.close() }
        let recorder = DriverRecorder(harness.driver)
        try harness.driver.start()
        _ = try await harness.driver.state()

        let driver = harness.driver
        let waiting = Task { await thrownError { _ = try await driver.commands() } }
        try await Task.sleep(for: .milliseconds(100))
        driver.shutdown()
        #expect(await waiting.value as? ConversationDriverError == .exited)
        #expect(recorder.didExit)
    }

    @Test func decodesModelsThinkingLevelsAndCommands() async throws {
        let harness = try FakePiHarness()
        defer { harness.close() }
        let recorder = DriverRecorder(harness.driver)
        try harness.driver.start()

        let models = try await harness.driver.availableModels()
        #expect(models.map(\.id) == ["fake-model", "fake-small"])
        #expect(try await harness.driver.availableThinkingLevels() == ["off", "low", "medium", "high"])
        #expect(try await harness.driver.commands().map(\.name) == ["fake-confirm"])
        try await harness.driver.setThinkingLevel("high")
        #expect(await waitUntil { recorder.events.contains(.thinkingLevelChanged("high")) })
        #expect(try await harness.driver.sessionStats().contextWindow == 100000)
    }
}
