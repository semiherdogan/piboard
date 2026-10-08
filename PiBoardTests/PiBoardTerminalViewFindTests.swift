import AppKit
import SwiftTerm
import Testing
@testable import PiBoard

@MainActor
struct PiBoardTerminalViewFindTests {
    private static let findBarTypeName = "TerminalFindBarView"

    // The bar is a SwiftTerm-internal type, so it is recognised by name.
    @Test func showFindBarAddsAVisibleFindBar() {
        let view = PiBoardTerminalView(frame: .zero, options: .default)
        view.showFindBar()
        let bar = view.subviews.first { String(describing: type(of: $0)) == Self.findBarTypeName }
        #expect(bar != nil)
        #expect(bar?.isHidden == false)
    }
}
