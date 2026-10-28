import Testing
@testable import PiBoard

struct AgentKindTests {
    @Test func titles() {
        #expect(AgentKind.pi.title == "Pi")
        #expect(AgentKind.opencode.title == "OpenCode")
    }
}
