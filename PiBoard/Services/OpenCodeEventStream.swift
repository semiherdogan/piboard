import Foundation
import Observation

/// One SSE connection per run to the OpenCode server, demultiplexed by session id into the
/// process manager. Reconnects with backoff; after each connect it resyncs Working from
/// `/api/session/active`, because events during a disconnection are lost by contract.
@MainActor
@Observable
final class OpenCodeEventStream {
    private static let startedType = "session.execution.started"
    private static let succeededType = "session.execution.succeeded"
    private static let failedType = "session.execution.failed"
    private static let interruptedType = "session.execution.interrupted"
    private static let permissionAskedType = "permission.asked"
    private static let permissionRepliedType = "permission.replied"
    private static let formCreatedType = "form.created"
    private static let formRepliedType = "form.replied"
    private static let formCancelledType = "form.cancelled"

    static let subscribedTypes = [
        startedType, succeededType, failedType, interruptedType,
        permissionAskedType, permissionRepliedType,
        formCreatedType, formRepliedType, formCancelledType,
    ]
    static let initialBackoff: Duration = .seconds(1)
    static let maxBackoff: Duration = .seconds(30)
    private static let backoffFactor = 2

    private(set) var isConnected = false

    @ObservationIgnored var onSettled: @MainActor (UUID) -> Void = { _ in }
    @ObservationIgnored var onNeedsInput: @MainActor (UUID) -> Void = { _ in }

    /// Task id per OpenCode session id, registered by the manager at launch and dropped on exit.
    private var taskIDs: [String: UUID] = [:]
    private var trackers: [UUID: AgentActivityTracker] = [:]
    private var streamTask: Task<Void, Never>?
    private let service: OpenCodeService
    private let processes: AgentProcessManager
    private let settleDelay: Duration

    init(service: OpenCodeService, processes: AgentProcessManager, settleDelay: Duration = AgentActivityTracker.defaultSettleDelay) {
        self.service = service
        self.processes = processes
        self.settleDelay = settleDelay
    }

    /// Called by the manager when an OpenCode task launches; starts the connection on the first registration.
    func register(sessionID: String, taskID: UUID) {
        taskIDs[sessionID] = taskID
        trackers[taskID]?.cancel()
        trackers[taskID] = AgentActivityTracker(settleDelay: settleDelay) { [weak self] in
            self?.onSettled(taskID)
        }
        if streamTask == nil {
            streamTask = Task { await run() }
        }
    }

    func unregister(taskID: UUID) {
        taskIDs = taskIDs.filter { $0.value != taskID }
        trackers.removeValue(forKey: taskID)?.cancel()
        processes.setExternalActivity(nil, for: taskID)
        if taskIDs.isEmpty {
            streamTask?.cancel()
            streamTask = nil
            isConnected = false
        }
    }

    /// Test seam: applies one decoded event as the stream would.
    func apply(_ event: OpenCodeEvent) {
        guard let sessionID = event.sessionID,
              let taskID = taskIDs[sessionID],
              let activity = Self.activity(for: event.type)
        else { return }
        set(activity, for: taskID)
        if activity == .needsInput {
            onNeedsInput(taskID)
        }
    }

    /// Test seam: lets a test await the delayed settle callback.
    func settleTask(for taskID: UUID) -> Task<Void, Never>? {
        trackers[taskID]?.settleTask
    }

    private static func activity(for type: String) -> AgentActivity? {
        switch type {
        case startedType, permissionRepliedType, formRepliedType, formCancelledType: .working
        case succeededType, failedType, interruptedType: .idle
        case permissionAskedType, formCreatedType: .needsInput
        default: nil
        }
    }

    private func set(_ activity: AgentActivity, for taskID: UUID) {
        processes.setExternalActivity(activity, for: taskID)
        trackers[taskID]?.handle(activity)
    }

    private func run() async {
        var backoff = Self.initialBackoff
        while !Task.isCancelled, !taskIDs.isEmpty {
            do {
                let client = try await service.client()
                // The snapshot is taken only once the server confirms the subscription, so a start between the two cannot be lost.
                var iterator = client.events(types: Self.subscribedTypes).makeAsyncIterator()
                guard let first = try await iterator.next() else { throw OpenCodeClientError.invalidResponse }
                guard first.type == OpenCodeClient.connectedEventType else { throw OpenCodeClientError.invalidResponse }
                applyResync(active: try await client.activeSessionIDs())
                isConnected = true
                backoff = Self.initialBackoff
                while let event = try await iterator.next() {
                    apply(event)
                }
            } catch OpenCodeClientError.unauthorized {
                await service.invalidate()
            } catch {
                Diagnostics.process.info("opencode event stream: \(error.localizedDescription, privacy: .public)")
            }
            isConnected = false
            guard !Task.isCancelled, !taskIDs.isEmpty else { return }
            try? await Task.sleep(for: backoff)
            backoff = min(backoff * Self.backoffFactor, Self.maxBackoff)
        }
    }

    /// Trackers ignore an idle for a session that never worked, so only real transitions settle.
    /// The active set does not say a session is blocked, so a pending needsInput is kept.
    func applyResync(active: Set<String>) {
        for (sessionID, taskID) in taskIDs {
            let isActive = active.contains(sessionID)
            if isActive, processes.externalActivity(for: taskID) == .needsInput {
                continue
            }
            set(isActive ? .working : .idle, for: taskID)
        }
    }
}
