import Foundation
import Testing
@testable import PiBoard

@MainActor
struct OpenCodeEventStreamTests {
    private static let sessionID = "ses_a"
    private static let settleDelay: Duration = .milliseconds(30)

    private final class Recorder {
        private(set) var settled: [UUID] = []
        private(set) var needsInput: [UUID] = []
        func settle(_ id: UUID) { settled.append(id) }
        func ask(_ id: UUID) { needsInput.append(id) }
    }

    private struct Fixture {
        let processes: AgentProcessManager
        let stream: OpenCodeEventStream
        let recorder = Recorder()
        let taskID = UUID()
    }

    private func makeFixture() -> Fixture {
        let processes = AgentProcessManager(agents: AgentRegistry([FakeAgentAdapter(activitySource: .serverEvents)]))
        // A nil executable makes the connect attempt fail at once; `apply` never connects anyway.
        let stream = OpenCodeEventStream(service: OpenCodeService(executable: { nil }), processes: processes, settleDelay: Self.settleDelay)
        let fixture = Fixture(processes: processes, stream: stream)
        processes.activitySources[fixture.taskID] = .serverEvents
        processes.runtimeStates[fixture.taskID] = .running
        stream.onSettled = { [recorder = fixture.recorder] in recorder.settle($0) }
        stream.onNeedsInput = { [recorder = fixture.recorder] in recorder.ask($0) }
        stream.register(sessionID: Self.sessionID, taskID: fixture.taskID)
        return fixture
    }

    private func event(_ type: String, sessionID: String? = OpenCodeEventStreamTests.sessionID) -> OpenCodeEvent {
        OpenCodeEvent(type: type, sessionID: sessionID, payload: Data())
    }

    @Test func startedMarksWorking() {
        let fixture = makeFixture()
        fixture.stream.apply(event("session.execution.started"))

        #expect(fixture.processes.agentActivity(for: fixture.taskID) == .working)
    }

    @Test func succeededMarksIdleAndSettles() async {
        let fixture = makeFixture()
        fixture.stream.apply(event("session.execution.started"))
        fixture.stream.apply(event("session.execution.succeeded"))

        #expect(fixture.processes.agentActivity(for: fixture.taskID) == .idle)
        await fixture.stream.settleTask(for: fixture.taskID)?.value
        #expect(fixture.recorder.settled == [fixture.taskID])
    }

    @Test func permissionAskedMarksNeedsInputAndNotifies() async {
        let fixture = makeFixture()
        fixture.stream.apply(event("session.execution.started"))
        fixture.stream.apply(event("permission.asked"))

        #expect(fixture.processes.agentActivity(for: fixture.taskID) == .needsInput)
        #expect(fixture.recorder.needsInput == [fixture.taskID])
        await fixture.stream.settleTask(for: fixture.taskID)?.value
        #expect(fixture.recorder.settled.isEmpty)
    }

    @Test func repliedReturnsToWorking() {
        let fixture = makeFixture()
        fixture.stream.apply(event("form.created"))
        #expect(fixture.processes.agentActivity(for: fixture.taskID) == .needsInput)

        fixture.stream.apply(event("form.replied"))
        #expect(fixture.processes.agentActivity(for: fixture.taskID) == .working)

        fixture.stream.apply(event("permission.asked"))
        fixture.stream.apply(event("permission.replied"))
        #expect(fixture.processes.agentActivity(for: fixture.taskID) == .working)
    }

    @Test func resyncKeepsNeedsInput() {
        let fixture = makeFixture()
        fixture.stream.apply(event("permission.asked"))

        fixture.stream.applyResync(active: [Self.sessionID])
        #expect(fixture.processes.agentActivity(for: fixture.taskID) == .needsInput)

        fixture.stream.apply(event("permission.replied"))
        fixture.stream.applyResync(active: [])
        #expect(fixture.processes.agentActivity(for: fixture.taskID) == .idle)

        fixture.stream.applyResync(active: [Self.sessionID])
        #expect(fixture.processes.agentActivity(for: fixture.taskID) == .working)
    }

    @Test func connectedEventIsIgnoredByApply() {
        let f = makeFixture()
        f.stream.apply(event(OpenCodeClient.connectedEventType, sessionID: nil))
        #expect(f.processes.externalActivity(for: f.taskID) == nil)
    }

    @Test func resyncKeepsWorkingSetByAnEarlierStart() {
        let f = makeFixture()
        f.stream.apply(event("session.execution.started"))
        f.stream.applyResync(active: [Self.sessionID])
        #expect(f.processes.externalActivity(for: f.taskID) == .working)
    }

    @Test func unknownSessionIsIgnored() {
        let fixture = makeFixture()
        fixture.stream.apply(event("session.execution.started", sessionID: "ses_other"))
        fixture.stream.apply(event("session.execution.started", sessionID: nil))

        #expect(fixture.processes.agentActivity(for: fixture.taskID) == nil)
    }

    @Test func unregisterClearsActivity() {
        let fixture = makeFixture()
        fixture.stream.apply(event("session.execution.started"))
        fixture.stream.unregister(taskID: fixture.taskID)

        #expect(fixture.processes.agentActivity(for: fixture.taskID) == nil)
        fixture.stream.apply(event("session.execution.started"))
        #expect(fixture.processes.agentActivity(for: fixture.taskID) == nil)
    }
}
