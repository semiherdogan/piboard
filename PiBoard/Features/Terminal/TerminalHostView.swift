import SwiftTerm
import SwiftUI

private let terminalInset: CGFloat = 10
private let missingLogValue = "none"

/// Owns the terminal view's frame via `layout()` instead of an autoresizing mask so the
/// frame is always derived from the current bounds, even on the first layout pass where
/// `updateNSView` would otherwise run before AppKit has assigned a real size to the container.
private final class TerminalContainerView: NSView {
    weak var terminalView: TerminalView?
    var taskID: UUID?
    let inset: CGFloat
    var didInitialLayout = false
    var onInitialLayout: (() -> Void)?

    init(inset: CGFloat) {
        self.inset = inset
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        if let terminalView {
            if bounds.width > 2 * inset && bounds.height > 2 * inset {
                terminalView.frame = bounds.insetBy(dx: inset, dy: inset)
            } else {
                terminalView.frame = bounds
            }
        }
        if !didInitialLayout, bounds.width > 0, bounds.height > 0 {
            didInitialLayout = true
            onInitialLayout?()
        }
    }
}

struct TerminalHostView: NSViewRepresentable {
    let taskID: UUID
    let session: PTYSession

    func makeNSView(context: Context) -> NSView {
        let container = TerminalContainerView(inset: terminalInset)
        container.wantsLayer = true
        container.clipsToBounds = true
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let container = nsView as? TerminalContainerView else { return }
        let terminalView = session.terminalView
        container.layer?.backgroundColor = terminalView.nativeBackgroundColor.cgColor
        if terminalView.superview !== container {
            // The same host serves a task across Resume and Start Fresh, each of which brings a new
            // session; the previous view must go or every swap stacks another terminal in here.
            if let previous = container.terminalView, previous !== terminalView {
                previous.removeFromSuperview()
            }
            terminalView.removeFromSuperview()
            terminalView.autoresizingMask = []
            container.addSubview(terminalView)
            container.terminalView = terminalView
            container.taskID = taskID
            container.onInitialLayout = { [weak session, weak container] in
                session?.syncWindowSize()
                if let container {
                    Self.log("initial layout", container: container)
                }
            }
            container.needsLayout = true
            // Deferred because the container is not in a window yet; only on attach so SwiftUI
            // updates never steal focus back from other controls.
            DispatchQueue.main.async { [weak container] in
                terminalView.window?.makeFirstResponder(terminalView)
                if let container {
                    Self.log("attach", container: container)
                }
            }
        }
    }

    static func dismantleNSView(_ container: NSView, coordinator: ()) {
        if let container = container as? TerminalContainerView {
            log("detach", container: container)
            if let terminalView = container.terminalView,
               let window = terminalView.window,
               window.firstResponder === terminalView {
                window.makeFirstResponder(nil)
            }
        }
        container.subviews.forEach { $0.removeFromSuperview() }
    }

    private static func log(_ event: String, container: TerminalContainerView) {
        let taskID = container.taskID?.uuidString ?? missingLogValue
        let terminalFrame = container.terminalView.map { NSStringFromRect($0.frame) } ?? missingLogValue
        let containerBounds = NSStringFromRect(container.bounds)
        let firstResponder = container.window?.firstResponder.map { String(describing: type(of: $0)) } ?? missingLogValue
        Diagnostics.ui.notice("terminal \(event, privacy: .public) task=\(taskID, privacy: .public) frame=\(terminalFrame, privacy: .public) bounds=\(containerBounds, privacy: .public) firstResponder=\(firstResponder, privacy: .public)")
    }
}
