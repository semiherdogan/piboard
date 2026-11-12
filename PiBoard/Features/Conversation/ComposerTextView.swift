import AppKit
import SwiftUI

private let composerMaxLines: CGFloat = 8
private let composerLineBreak = "\n"
private let composerTextInset = NSSize.zero
private let composerLineFragmentPadding: CGFloat = 0
private let composerFallbackWidth: CGFloat = 100
private let composerMeasureExtraLines: CGFloat = 1
private let composerLegacyFilenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
// Image and file types a paste may carry; the text view only reads them to hand them to the composer.
private let composerAttachmentPasteTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, .fileURL]

/// Plain-text multi-line input that grows to eight lines; key handling goes through `onCommand` so it is the same on every path.
struct ComposerTextView: NSViewRepresentable {
    /// What the composer decides; a `false` answer lets the text view do its default.
    enum Command {
        case submit
        case cancel
        case moveUp
        case moveDown
        case complete
    }

    @Binding var text: String
    let placeholder: String
    let isEnabled: Bool
    // Bumped by the composer to take focus back, for example after a command was picked with the mouse.
    let focusToken: Int
    let accessibilityID: String
    let onCommand: (Command) -> Bool
    let onPasteAttachment: (NSPasteboard) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ComposerNSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        // Prompts contain code, flags and paths that smart substitutions would corrupt.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.drawsBackground = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.textContainerInset = composerTextInset
        textView.textContainer?.lineFragmentPadding = composerLineFragmentPadding
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.setAccessibilityIdentifier(accessibilityID)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        context.coordinator.textView = textView
        // The window does not exist yet; same deferral as the terminal host.
        DispatchQueue.main.async { [weak textView] in
            textView?.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ComposerNSTextView else { return }
        let coordinator = context.coordinator
        coordinator.parent = self
        textView.placeholder = placeholder
        textView.isEditable = isEnabled
        textView.onCommand = onCommand
        textView.onPasteAttachment = onPasteAttachment
        // The frame must cover the visible area or clicks below the last line miss the view.
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        // Replacing text while an input method is composing would cancel the composition.
        if textView.string != text, !textView.hasMarkedText() {
            coordinator.isApplyingExternalText = true
            textView.replaceContents(with: text)
            coordinator.isApplyingExternalText = false
        }
        if coordinator.lastFocusToken != focusToken {
            coordinator.lastFocusToken = focusToken
            textView.window?.makeFirstResponder(textView)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView scrollView: NSScrollView, context: Context) -> CGSize? {
        guard let textView = scrollView.documentView as? ComposerNSTextView else { return nil }
        let width = proposal.width ?? (scrollView.frame.width > 0 ? scrollView.frame.width : composerFallbackWidth)
        return CGSize(width: width, height: textView.fittingHeight(forWidth: width))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var textView: ComposerNSTextView?
        var lastFocusToken = 0
        // The binding already holds this text; writing it back during a view update would loop.
        var isApplyingExternalText = false

        init(parent: ComposerTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalText, let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

final class ComposerNSTextView: NSTextView {
    var onCommand: ((ComposerTextView.Command) -> Bool)?
    var onPasteAttachment: ((NSPasteboard) -> Void)?
    var placeholder = ""
    private var contentRevision = 0
    private var measuredRevision = -1
    private var measuringStack: (storage: NSTextContentStorage, layout: NSTextLayoutManager, container: NSTextContainer)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let origin = NSPoint(x: textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0), y: textContainerOrigin.y)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: NSColor.placeholderTextColor,
        ]
        placeholder.draw(at: origin, withAttributes: attributes)
    }

    override func didChangeText() {
        contentRevision += 1
        super.didChangeText()
        needsDisplay = true
    }

    /// Goes through the text system so the change is undoable; a send clears the stack so Cmd+Z cannot bring the sent text back.
    func replaceContents(with text: String) {
        let full = NSRange(location: 0, length: (string as NSString).length)
        guard shouldChangeText(in: full, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: full, with: NSAttributedString(string: text, attributes: typingAttributes))
        didChangeText()
        setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        if text.isEmpty { undoManager?.removeAllActions() }
    }

    /// One line up to `composerMaxLines`; beyond that the scroll view scrolls.
    func fittingHeight(forWidth width: CGFloat) -> CGFloat {
        let font = font ?? NSFont.preferredFont(forTextStyle: .body)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        guard width > 0 else { return lineHeight }
        let stack = measuringStack(attributedText: attributedString())
        stack.container.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        // Laying out past the cap is wasted: the height is clamped anyway.
        let cap = lineHeight * composerMaxLines
        let stopAt = lineHeight * (composerMaxLines + composerMeasureExtraLines)
        var used: CGFloat = 0
        stack.layout.enumerateTextLayoutFragments(from: stack.layout.documentRange.location, options: [.ensuresLayout]) { fragment in
            used = max(used, fragment.layoutFragmentFrame.maxY)
            return used < stopAt
        }
        return min(max(ceil(used), lineHeight), cap)
    }

    // A private layout stack keeps the live container's width untouched by probes.
    private func measuringStack(attributedText: @autoclosure () -> NSAttributedString) -> (storage: NSTextContentStorage, layout: NSTextLayoutManager, container: NSTextContainer) {
        let stack = measuringStack ?? {
            let storage = NSTextContentStorage()
            let layout = NSTextLayoutManager()
            let container = NSTextContainer()
            container.lineFragmentPadding = textContainer?.lineFragmentPadding ?? composerLineFragmentPadding
            layout.textContainer = container
            storage.addTextLayoutManager(layout)
            return (storage, layout, container)
        }()
        measuringStack = stack
        if measuredRevision != contentRevision {
            measuredRevision = contentRevision
            stack.storage.attributedString = attributedText()
        }
        return stack
    }

    // Adding the image and file types to the readable list is what enables Paste in the Edit menu for an image-only pasteboard.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        super.readablePasteboardTypes + composerAttachmentPasteTypes
    }

    // Dropped files must reach the chat's drop target as attachments, not be pasted as path text.
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes.filter { $0 != .fileURL && $0 != composerLegacyFilenamesType }
    }

    override func readSelection(from pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard composerAttachmentPasteTypes.contains(type) else { return super.readSelection(from: pasteboard, type: type) }
        onPasteAttachment?(pasteboard)
        return true
    }

    // Text wins over an image so a Numbers or Word copy pastes as text; copied files win over their name.
    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if ChatAttachment.isAttachmentPaste(on: pasteboard) {
            onPasteAttachment?(pasteboard)
        } else {
            super.paste(sender)
        }
    }

    override func doCommand(by selector: Selector) {
        let command: ComposerTextView.Command? = switch selector {
        case #selector(NSResponder.insertNewline(_:)): .submit
        case #selector(NSResponder.cancelOperation(_:)): .cancel
        case #selector(NSResponder.moveUp(_:)): .moveUp
        case #selector(NSResponder.moveDown(_:)): .moveDown
        case #selector(NSResponder.insertTab(_:)): .complete
        default: nil
        }
        if selector == #selector(NSResponder.insertLineBreak(_:)) || isShiftReturn(selector) {
            insertText(composerLineBreak, replacementRange: selectedRange())
            return
        }
        if let command, onCommand?(command) == true { return }
        super.doCommand(by: selector)
    }

    private func isShiftReturn(_ selector: Selector) -> Bool {
        selector == #selector(NSResponder.insertNewline(_:)) && NSApp.currentEvent?.modifierFlags.contains(.shift) == true
    }
}
