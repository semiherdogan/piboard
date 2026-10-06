import AppKit
import SwiftTerm

private let copyMenuItemTitle = "Copy"
private let copyTrimmedMenuItemTitle = "Copy Trimmed"
private let pasteMenuItemTitle = "Paste"
private let selectAllMenuItemTitle = "Select All"

/// `TerminalView` does not override `menu(for:)`, so `NSView`'s default handling already
/// routes right-clicks through it; no `rightMouseDown` override is needed.
final class PiBoardTerminalView: TerminalView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

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
}
