import SwiftTerm
import SwiftUI

private let terminalInset: CGFloat = 10

/// Owns the terminal view's frame via `layout()` instead of an autoresizing mask so the
/// frame is always derived from the current bounds, even on the first layout pass where
/// `updateNSView` would otherwise run before AppKit has assigned a real size to the container.
private final class TerminalContainerView: NSView {
    weak var terminalView: TerminalView?
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
    let session: PTYSession

    func makeNSView(context: Context) -> NSView {
        let container = TerminalContainerView(inset: terminalInset)
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let container = nsView as? TerminalContainerView else { return }
        let terminalView = session.terminalView
        container.layer?.backgroundColor = terminalView.nativeBackgroundColor.cgColor
        if terminalView.superview !== container {
            terminalView.removeFromSuperview()
            terminalView.autoresizingMask = []
            container.addSubview(terminalView)
            container.terminalView = terminalView
            container.onInitialLayout = { [weak session] in
                session?.syncWindowSize()
            }
            container.needsLayout = true
        }
        DispatchQueue.main.async {
            terminalView.window?.makeFirstResponder(terminalView)
        }
    }

    static func dismantleNSView(_ container: NSView, coordinator: ()) {
        container.subviews.forEach { $0.removeFromSuperview() }
    }
}
