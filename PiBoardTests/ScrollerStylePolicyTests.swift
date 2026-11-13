import AppKit
import Foundation
import Testing
@testable import PiBoard

@MainActor
struct ScrollerStylePolicyTests {
    @Test func writesTheOverlayValueIntoTheGivenDefaults() throws {
        let suite = "ScrollerStylePolicyTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        ScrollerStylePolicy.apply(to: defaults)

        #expect(defaults.string(forKey: ScrollerStylePolicy.defaultsKey) == ScrollerStylePolicy.overlayValue)
    }

    @Test func theHostedAppUsesOverlayScrollers() {
        #expect(NSScroller.preferredScrollerStyle == .overlay)
    }
}
