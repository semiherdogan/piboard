import Foundation
import Testing
@testable import PiBoard

@MainActor
struct AgentActivityTrackerTests {
    // Short enough to keep the suite fast, long enough that a cancellation still wins the race.
    private static let settleDelay: Duration = .milliseconds(30)

    private final class SettleCount {
        private(set) var value = 0
        func increment() { value += 1 }
    }

    private func tracker(_ count: SettleCount) -> AgentActivityTracker {
        AgentActivityTracker(settleDelay: Self.settleDelay) { count.increment() }
    }

    @Test func reportsOnceTheAgentHasStoppedWorking() async {
        let count = SettleCount()
        let tracker = tracker(count)
        tracker.handle(.working)
        tracker.handle(.idle)
        await tracker.settleTask?.value
        #expect(count.value == 1)
    }

    // Pi clears progress when it exits too; a terminal that never worked has nothing to announce.
    @Test func idleWithoutPrecedingWorkIsIgnored() async {
        let count = SettleCount()
        let tracker = tracker(count)
        tracker.handle(.idle)
        await tracker.settleTask?.value
        #expect(count.value == 0)
    }

    // An automatic retry or a compaction pass starts another turn right after `agent_end`, and
    // that must extend the same stretch of work rather than announce it twice.
    @Test func workResumingInsideTheWindowCancelsTheReport() async {
        let count = SettleCount()
        let tracker = tracker(count)
        tracker.handle(.working)
        tracker.handle(.idle)
        tracker.handle(.working)
        await tracker.settleTask?.value
        #expect(count.value == 0)

        tracker.handle(.idle)
        await tracker.settleTask?.value
        #expect(count.value == 1)
    }

    @Test func keepaliveRepeatsDoNotReportAnything() async {
        let count = SettleCount()
        let tracker = tracker(count)
        for _ in 0..<5 {
            tracker.handle(.working)
        }
        await tracker.settleTask?.value
        #expect(count.value == 0)
    }

    @Test func twoSeparateTurnsReportTwice() async {
        let count = SettleCount()
        let tracker = tracker(count)
        for _ in 0..<2 {
            tracker.handle(.working)
            tracker.handle(.idle)
            await tracker.settleTask?.value
        }
        #expect(count.value == 2)
    }

    // Quitting Pi clears progress as it shuts down, which is not the agent finishing a turn.
    @Test func cancelDropsAPendingReport() async {
        let count = SettleCount()
        let tracker = tracker(count)
        tracker.handle(.working)
        tracker.handle(.idle)
        tracker.cancel()
        try? await Task.sleep(for: Self.settleDelay * 3)
        #expect(count.value == 0)
    }
}
