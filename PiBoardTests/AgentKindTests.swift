import AppKit
import Testing
@testable import PiBoard

struct AgentKindTests {
    @Test func titles() {
        #expect(AgentKind.pi.title == "Pi")
        #expect(AgentKind.opencode.title == "OpenCode")
        #expect(AgentKind.claudeCode.title == "Claude Code")
    }

    @Test func everyKindHasASymbolAndShortTitle() {
        for kind in AgentKind.allCases {
            #expect(!kind.shortTitle.isEmpty)
            #expect(!kind.systemImage.isEmpty)
            #expect(NSImage(systemSymbolName: kind.systemImage, accessibilityDescription: nil) != nil)
        }
    }
}
