import SwiftUI

struct TerminalHostView: NSViewRepresentable {
    let session: PTYSession

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ container: NSView, context: Context) {
        let terminalView = session.terminalView
        if terminalView.superview !== container {
            terminalView.removeFromSuperview()
            terminalView.autoresizingMask = [.width, .height]
            terminalView.frame = container.bounds
            container.addSubview(terminalView)
        }
        DispatchQueue.main.async {
            terminalView.window?.makeFirstResponder(terminalView)
        }
    }

    static func dismantleNSView(_ container: NSView, coordinator: ()) {
        container.subviews.forEach { $0.removeFromSuperview() }
    }
}
