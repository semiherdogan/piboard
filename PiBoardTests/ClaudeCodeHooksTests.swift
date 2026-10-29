import Foundation
import Testing
@testable import PiBoard

@MainActor
struct ClaudeCodeHooksTests {
    private let server = FakeHookServer()
    private let sessionID = "0b0c7f0e-1c2d-4e5f-8a9b-0c1d2e3f4a5b"
    private let taskID = UUID()

    private func token(in settings: String?) throws -> String {
        let settings = try #require(settings)
        let url = try #require(settings.components(separatedBy: ClaudeCodeHooks.pathPrefix).dropFirst().first)
        return String(try #require(url.split(separator: "\"").first))
    }

    private func body(_ event: String, sessionID: String? = nil) -> Data {
        let object: [String: String] = [ClaudeCodeHooks.eventNameKey: event, ClaudeCodeHooks.sessionIDKey: sessionID ?? self.sessionID]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    private func makeRecordingHooks() async -> (ClaudeCodeHooks, Recorder) {
        let hooks = ClaudeCodeHooks(server: server)
        await hooks.start()
        let recorder = Recorder()
        hooks.onActivity = { recorder.activities.append(Activity(taskID: $0, activity: $1)) }
        hooks.onNeedsInput = { recorder.needsInput.append($0) }
        return (hooks, recorder)
    }

    @MainActor
    private final class Recorder {
        var activities: [Activity] = []
        var needsInput: [UUID] = []
    }

    private struct Activity: Equatable {
        let taskID: UUID
        let activity: AgentActivity?
    }

    @Test func settingsJSONSubscribesEveryEventOverHTTP() async throws {
        let hooks = ClaudeCodeHooks(server: server)
        await hooks.start()
        let json = try #require(hooks.settingsJSON(sessionID: sessionID))

        #expect(json.contains("http://127.0.0.1:\(FakeHookServer.port)/hooks/"))
        #expect(json.contains(#""type":"http""#))
        for event in ClaudeCodeHooks.subscribedEvents {
            #expect(json.contains("\"\(event)\""))
        }
        #expect(server.startCount == 1)
    }

    @Test func settingsJSONIsNilBeforeStart() {
        #expect(ClaudeCodeHooks(server: server).settingsJSON(sessionID: sessionID) == nil)
    }

    @Test func aSecondStartDoesNotCallTheServerAgain() async {
        let hooks = ClaudeCodeHooks(server: server)

        await hooks.start()
        await hooks.start()

        #expect(server.startCount == 1)
    }

    @Test func concurrentStartsShareOneServerStart() async {
        let hooks = ClaudeCodeHooks(server: server)

        async let first: Void = hooks.start()
        async let second: Void = hooks.start()
        _ = await (first, second)

        #expect(server.startCount == 1)
    }

    @Test func aSecondSettingsCallReplacesTheToken() async throws {
        let (hooks, recorder) = await makeRecordingHooks()
        hooks.register(sessionID: sessionID, taskID: taskID)
        let first = try token(in: hooks.settingsJSON(sessionID: sessionID))
        let second = try token(in: hooks.settingsJSON(sessionID: sessionID))

        hooks.apply(path: ClaudeCodeHooks.pathPrefix + first, body: body(ClaudeCodeHooks.permissionRequestEvent))
        #expect(first != second)
        #expect(recorder.activities.isEmpty)

        hooks.apply(path: ClaudeCodeHooks.pathPrefix + second, body: body(ClaudeCodeHooks.permissionRequestEvent))
        #expect(recorder.activities.count == 1)
    }

    @Test func permissionRequestMarksNeedsInput() async throws {
        let (hooks, recorder) = await makeRecordingHooks()
        hooks.register(sessionID: sessionID, taskID: taskID)
        let token = try token(in: hooks.settingsJSON(sessionID: sessionID))

        hooks.apply(path: ClaudeCodeHooks.pathPrefix + token, body: body(ClaudeCodeHooks.permissionRequestEvent))

        #expect(recorder.activities == [Activity(taskID: taskID, activity: .needsInput)])
        #expect(recorder.needsInput == [taskID])
    }

    @Test(arguments: [
        ClaudeCodeHooks.userPromptSubmitEvent, ClaudeCodeHooks.stopEvent,
        ClaudeCodeHooks.stopFailureEvent, ClaudeCodeHooks.sessionEndEvent,
    ])
    func clearingEventsResetTheActivity(event: String) async throws {
        let (hooks, recorder) = await makeRecordingHooks()
        hooks.register(sessionID: sessionID, taskID: taskID)
        let token = try token(in: hooks.settingsJSON(sessionID: sessionID))

        hooks.apply(path: ClaudeCodeHooks.pathPrefix + token, body: body(event))

        #expect(recorder.activities == [Activity(taskID: taskID, activity: nil)])
        #expect(recorder.needsInput.isEmpty)
    }

    @Test func unknownEventsAreIgnored() async throws {
        let (hooks, recorder) = await makeRecordingHooks()
        hooks.register(sessionID: sessionID, taskID: taskID)
        let token = try token(in: hooks.settingsJSON(sessionID: sessionID))

        hooks.apply(path: ClaudeCodeHooks.pathPrefix + token, body: body("Notification"))

        #expect(recorder.activities.isEmpty)
    }

    @Test func anUnknownTokenIsIgnored() async {
        let (hooks, recorder) = await makeRecordingHooks()
        hooks.register(sessionID: sessionID, taskID: taskID)
        _ = hooks.settingsJSON(sessionID: sessionID)

        hooks.apply(path: ClaudeCodeHooks.pathPrefix + "unknown", body: body(ClaudeCodeHooks.stopEvent))

        #expect(recorder.activities.isEmpty)
    }

    @Test func aMismatchedSessionIDIsIgnored() async throws {
        let (hooks, recorder) = await makeRecordingHooks()
        hooks.register(sessionID: sessionID, taskID: taskID)
        let token = try token(in: hooks.settingsJSON(sessionID: sessionID))

        hooks.apply(path: ClaudeCodeHooks.pathPrefix + token, body: body(ClaudeCodeHooks.stopEvent, sessionID: "other"))

        #expect(recorder.activities.isEmpty)
    }

    @Test func unregisteringTheLastTaskKeepsTheServer() async {
        let hooks = ClaudeCodeHooks(server: server)
        await hooks.start()
        hooks.register(sessionID: sessionID, taskID: taskID)

        hooks.unregister(taskID: taskID)

        #expect(server.stopCount == 0)
        #expect(hooks.settingsJSON(sessionID: sessionID) != nil)
    }

    @Test func unregisteringDropsTheTaskToken() async throws {
        let (hooks, recorder) = await makeRecordingHooks()
        hooks.register(sessionID: sessionID, taskID: taskID)
        let token = try token(in: hooks.settingsJSON(sessionID: sessionID))

        hooks.unregister(taskID: taskID)
        hooks.apply(path: ClaudeCodeHooks.pathPrefix + token, body: body(ClaudeCodeHooks.stopEvent))

        #expect(recorder.activities.isEmpty)
    }

    @Test func aFailingStartLeavesSettingsNil() async {
        server.startError = LoopbackHookServerError.failed("boom")
        let hooks = ClaudeCodeHooks(server: server)

        await hooks.start()

        #expect(hooks.settingsJSON(sessionID: sessionID) == nil)
    }
}
