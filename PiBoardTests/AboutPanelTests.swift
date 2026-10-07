import AppKit
import Testing
@testable import PiBoard

@MainActor
struct AboutPanelTests {
    @Test func creditsCarryTheRepositoryAsAClickableLink() {
        let credits = AboutPanel.credits
        var range = NSRange()
        let link = credits.attribute(.link, at: 0, effectiveRange: &range) as? URL
        #expect(link == AboutPanel.repositoryURL)
        // The whole string is the link, so there is nothing in the panel that looks clickable
        // but is not.
        #expect(range == NSRange(location: 0, length: credits.length))
    }

    @Test func theRepositoryIsAnHTTPSAddress() {
        #expect(AboutPanel.repositoryURL.scheme == "https")
        #expect(AboutPanel.repositoryURL.host() == "github.com")
    }
}
