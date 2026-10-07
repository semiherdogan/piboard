import Foundation

/// What the terminal's progress reporting says the agent is doing right now.
enum AgentActivity: Equatable, Sendable {
    case working
    case idle
}

/// Turns Pi's progress reporting into a single "the agent finished" callback.
///
/// Pi writes `OSC 9;4;3` when a turn starts and `OSC 9;4;0` when the agent ends, re-sending the
/// busy sequence once a second as a keepalive. The end is not final: an automatic retry or a
/// compaction pass starts another turn right after, each toggling the same pair. Settling is
/// therefore delayed, and any new activity inside that window cancels it, so one notification
/// covers a whole stretch of work instead of one per internal step.
@MainActor
final class AgentActivityTracker {
    /// Comfortably above Pi's one second keepalive, so a pause between turns is not read as the end.
    static let defaultSettleDelay: Duration = .seconds(2)

    private let settleDelay: Duration
    private let onSettled: @MainActor () -> Void
    private var isWorking = false
    /// Exposed so tests can await the delayed callback instead of sleeping.
    private(set) var settleTask: Task<Void, Never>?

    init(settleDelay: Duration = defaultSettleDelay, onSettled: @escaping @MainActor () -> Void) {
        self.settleDelay = settleDelay
        self.onSettled = onSettled
    }

    deinit {
        settleTask?.cancel()
    }

    func handle(_ activity: AgentActivity) {
        switch activity {
        case .working:
            isWorking = true
            settleTask?.cancel()
            settleTask = nil
        case .idle:
            // Pi clears progress on exit too, and a terminal that was never busy has nothing to
            // report, so only a transition out of work counts.
            guard isWorking else { return }
            isWorking = false
            settleTask?.cancel()
            settleTask = Task { [settleDelay, onSettled] in
                try? await Task.sleep(for: settleDelay)
                guard !Task.isCancelled else { return }
                onSettled()
            }
        }
    }

    /// Drops a pending callback when the session goes away, so a terminated agent stays quiet.
    func cancel() {
        isWorking = false
        settleTask?.cancel()
        settleTask = nil
    }
}
