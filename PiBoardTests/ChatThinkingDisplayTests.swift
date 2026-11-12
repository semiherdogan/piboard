import Testing
@testable import PiBoard

struct ChatThinkingDisplayTests {
    @Test func cyclesThroughEveryMode() {
        #expect(ChatThinkingDisplay.hidden.next == .collapsed)
        #expect(ChatThinkingDisplay.collapsed.next == .expanded)
        #expect(ChatThinkingDisplay.expanded.next == .hidden)
    }
}
