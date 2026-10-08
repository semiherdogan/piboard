import AppKit
import SwiftTerm

private let copyMenuItemTitle = "Copy"
private let copyTrimmedMenuItemTitle = "Copy Trimmed"
private let pasteMenuItemTitle = "Paste"
private let selectAllMenuItemTitle = "Select All"
private let selectWithShiftMenuItemTitle = "Hold Shift and drag to select in the terminal"

// SwiftTerm publishes the DEC 2004 sequences as mutable statics, which Swift 6 refuses to read
// from an isolated context, so they are spelled out here instead.
private let bracketedPasteStart = "\u{1b}[200~"
private let bracketedPasteEnd = "\u{1b}[201~"

/// `TerminalView` does not override `menu(for:)`, so `NSView`'s default handling already
/// routes right-clicks through it; no `rightMouseDown` override is needed.
final class PiBoardTerminalView: TerminalView {
    override init(frame: CGRect, font: NSFont? = nil, options: TerminalOptions) {
        super.init(frame: frame, font: font, options: options)
        // SwiftTerm registers no dragged types, so dropped files would otherwise be refused.
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PiBoardTerminalView is created in code, never from a nib")
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        // Without this, AppKit calls validateUserInterfaceItem(_:) instead of honoring isEnabled below.
        menu.autoenablesItems = false

        // When mouse reporting is on, the child app owns drag selection and the view never gets one;
        // showing disabled Copy items then looks broken, so point the user at Shift-drag instead.
        if !selectionActive && getTerminal().mouseMode != .off {
            let selectWithShiftItem = NSMenuItem(title: selectWithShiftMenuItemTitle, action: nil, keyEquivalent: "")
            selectWithShiftItem.isEnabled = false
            menu.addItem(selectWithShiftItem)
        } else {
            let copyItem = NSMenuItem(title: copyMenuItemTitle, action: #selector(copy(_:)), keyEquivalent: "")
            copyItem.target = self
            copyItem.isEnabled = selectionActive
            menu.addItem(copyItem)

            let copyTrimmedItem = NSMenuItem(
                title: copyTrimmedMenuItemTitle,
                action: #selector(copyTrimmed(_:)),
                keyEquivalent: ""
            )
            copyTrimmedItem.target = self
            copyTrimmedItem.isEnabled = selectionActive
            menu.addItem(copyTrimmedItem)
        }

        menu.addItem(.separator())

        let pasteItem = NSMenuItem(title: pasteMenuItemTitle, action: #selector(paste(_:)), keyEquivalent: "")
        pasteItem.target = self
        pasteItem.isEnabled = NSPasteboard.general.string(forType: .string) != nil
        menu.addItem(pasteItem)

        menu.addItem(.separator())

        let selectAllItem = NSMenuItem(
            title: selectAllMenuItemTitle,
            action: #selector(selectAllAction(_:)),
            keyEquivalent: ""
        )
        selectAllItem.target = self
        menu.addItem(selectAllItem)

        return menu
    }

    @objc private func copyTrimmed(_ sender: Any?) {
        let trimmed = TerminalTextTrimmer.trim(getSelection())
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(trimmed, forType: .string)
    }

    @objc private func selectAllAction(_ sender: Any?) {
        selectAll(sender)
    }

    /// SwiftTerm's `showFindBar` is private; the public route is the text finder action it
    /// already handles, so a stand-in menu item carries the action tag.
    func showFindBar() {
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        performTextFinderAction(item)
    }

    // MARK: Dropping files

    // `canReadObject` rather than `readObjects` because dragging updates fire continuously and
    // only the answer, not the URLs, is needed until the drop happens.
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        acceptsFiles(sender) ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        acceptsFiles(sender) ? .copy : []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: Self.draggedURLReadingOptions
        ) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        paste(text: DroppedFilePaths.text(for: urls))
        return true
    }

    private static var draggedURLReadingOptions: [NSPasteboard.ReadingOptionKey: Any] {
        [.urlReadingFileURLsOnly: true]
    }

    private func acceptsFiles(_ sender: any NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: Self.draggedURLReadingOptions)
    }

    /// Sends text the way a paste would. Pi's prompt uses bracketed paste to tell pasted text from
    /// typing, so a drop that skipped the markers could be read as keystrokes and trigger bindings.
    private func paste(text: String) {
        guard getTerminal().bracketedPasteMode else {
            send(txt: text)
            return
        }
        send(txt: bracketedPasteStart + text + bracketedPasteEnd)
    }

    // SwiftTerm's TerminalView implements this and would otherwise override our enabled state
    // if these items ever end up in the main menu bar.
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copyTrimmed(_:)):
            return selectionActive
        case #selector(selectAllAction(_:)):
            return true
        default:
            return super.validateUserInterfaceItem(item)
        }
    }
}
