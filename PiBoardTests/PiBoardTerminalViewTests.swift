import AppKit
import SwiftTerm
import Testing
@testable import PiBoard

private let alternateScreenWithSGRButtonTracking = "\u{1b}[?1049h\u{1b}[?1000h\u{1b}[?1006h"
private let sgrMousePrefix = "\u{1b}[<"
private let csiCursorUp = "\u{1b}[A"
private let ss3CursorUp = "\u{1b}OA"
private let viewSize = CGSize(width: 800, height: 600)
private let clickPoint = CGPoint(width: 100, height: 100)
private let dragEndPoint = CGPoint(width: 300, height: 100)
private let outputLine = Array("x\r\n".utf8)[...]

private extension CGPoint {
    init(width: CGFloat, height: CGFloat) { self.init(x: width, y: height) }
}

private final class CapturingTerminalDelegate: TerminalViewDelegate {
    private(set) var sent = ""

    func clearSent() { sent = "" }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        sent += String(decoding: data, as: UTF8.self)
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func bell(source: TerminalView) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
}

@MainActor
struct PiBoardTerminalViewTests {
    private func makeView() -> (PiBoardTerminalView, CapturingTerminalDelegate) {
        let view = PiBoardTerminalView(frame: CGRect(origin: .zero, size: viewSize), options: .default)
        let delegate = CapturingTerminalDelegate()
        view.terminalDelegate = delegate
        view.feed(text: alternateScreenWithSGRButtonTracking)
        view.selectsWithoutShift = true
        return (view, delegate)
    }

    private func mouseEvent(_ type: NSEvent.EventType, at location: CGPoint = clickPoint) throws -> NSEvent {
        try #require(
            NSEvent.mouseEvent(
                with: type,
                location: location,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )
    }

    @Test func wheelStillReportsToAgentWhenSelectingWithoutShift() throws {
        let (view, delegate) = makeView()
        let cgEvent = try #require(
            CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 1,
                wheel1: 1,
                wheel2: 0,
                wheel3: 0
            )
        )
        let event = try #require(NSEvent(cgEvent: cgEvent))

        view.scrollWheel(with: event)

        #expect(delegate.sent.hasPrefix(sgrMousePrefix))
        #expect(!delegate.sent.contains(csiCursorUp))
        #expect(!delegate.sent.contains(ss3CursorUp))
    }

    @Test func clickIsNotReportedToAgentWhenSelectingWithoutShift() throws {
        let (view, delegate) = makeView()
        delegate.clearSent()

        view.mouseDown(with: try mouseEvent(.leftMouseDown))
        view.mouseUp(with: try mouseEvent(.leftMouseUp))

        #expect(!delegate.sent.contains(sgrMousePrefix))
        #expect(view.allowMouseReporting == true)
    }

    private func dragSelection(_ view: PiBoardTerminalView) throws {
        view.mouseDown(with: try mouseEvent(.leftMouseDown))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, at: dragEndPoint))
        view.mouseUp(with: try mouseEvent(.leftMouseUp, at: dragEndPoint))
    }

    @Test func dragIsNotReportedToAgentWhenSelectingWithoutShift() throws {
        let (view, delegate) = makeView()
        delegate.clearSent()

        try dragSelection(view)

        #expect(!delegate.sent.hasPrefix(sgrMousePrefix))
        #expect(!delegate.sent.contains(sgrMousePrefix))
    }

    @Test func selectionSurvivesOutputWhenSelectingWithoutShift() throws {
        let (view, _) = makeView()
        try dragSelection(view)
        #expect(view.selectionActive)

        view.feedOutput(outputLine)

        #expect(view.selectionActive)
        #expect(view.allowMouseReporting == true)
    }

    @Test func outputClearsSelectionWhenNotSelectingWithoutShift() {
        let (view, _) = makeView()
        view.selectsWithoutShift = false
        view.selectAll(nil)
        #expect(view.selectionActive)

        view.feedOutput(outputLine)

        #expect(!view.selectionActive)
    }
}
