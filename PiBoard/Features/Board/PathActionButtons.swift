import AppKit
import SwiftUI

private let copyPathTitle = "Copy Path"
private let revealInFinderTitle = "Open in Finder"
private let copySystemImage = "doc.on.doc"
private let revealSystemImage = "folder"
private let remoteSystemImage = "globe"
private let buttonSpacing: CGFloat = 8

/// Copy, Finder and, when the repository has a browsable remote, its web page; shared by the board
/// header and the terminal header so both offer the same quick access to a folder.
struct PathActionButtons: View {
    let path: URL
    var remoteURL: URL?

    static func remoteHelp(_ url: URL) -> String {
        "Open \(url.host() ?? "remote") in Browser"
    }

    var body: some View {
        HStack(spacing: buttonSpacing) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path.path, forType: .string)
            } label: {
                Image(systemName: copySystemImage)
            }
            .help(copyPathTitle)
            .accessibilityLabel(copyPathTitle)
            .accessibilityIdentifier(AccessibilityID.pathCopy)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([path])
            } label: {
                Image(systemName: revealSystemImage)
            }
            .help(revealInFinderTitle)
            .accessibilityLabel(revealInFinderTitle)
            .accessibilityIdentifier(AccessibilityID.pathReveal)
            .disabled(!ProjectPathService.exists(path))

            if let remoteURL {
                Button {
                    NSWorkspace.shared.open(remoteURL)
                } label: {
                    Image(systemName: remoteSystemImage)
                }
                .help(Self.remoteHelp(remoteURL))
                .accessibilityLabel(Self.remoteHelp(remoteURL))
                .accessibilityIdentifier(AccessibilityID.pathRemote)
            }
        }
        .buttonStyle(.plain)
    }
}
