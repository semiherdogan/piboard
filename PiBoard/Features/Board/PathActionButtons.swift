import AppKit
import SwiftUI

private let copyPathTitle = "Copy Path"
private let copiedTitle = "Copied"
private let revealInFinderTitle = "Open in Finder"
private let copySystemImage = "doc.on.doc"
private let copiedSystemImage = "checkmark"
private let revealSystemImage = "folder"
private let remoteSystemImage = "globe"
private let copiedDuration: Duration = .seconds(1.5)

/// Copy, Finder and, when the repository has a browsable remote, its web page; shared by the board
/// header and the terminal header so both offer the same quick access to a folder.
struct PathActionButtons: View {
    let path: URL
    var remoteURL: URL?
    @State private var copiedAt: Date?

    static func remoteHelp(_ url: URL) -> String {
        "Open \(url.host() ?? "remote") in Browser"
    }

    var body: some View {
        HStack(spacing: headerIconButtonSpacing) {
            Button(action: copy) {
                Image(systemName: copiedAt == nil ? copySystemImage : copiedSystemImage)
                    .contentTransition(.symbolEffect(.replace))
            }
            .help(copiedAt == nil ? copyPathTitle : copiedTitle)
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
        .buttonStyle(.headerIcon)
        // The terminal reuses this view across tasks; a check mark belongs to the path it copied.
        .onChange(of: path) { copiedAt = nil }
        // A new click restarts the check mark, and only the latest click clears it.
        .task(id: copiedAt) {
            guard copiedAt != nil else { return }
            try? await Task.sleep(for: copiedDuration)
            guard !Task.isCancelled else { return }
            withAnimation { copiedAt = nil }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path.path, forType: .string)
        withAnimation { copiedAt = Date() }
    }
}
