import SwiftUI

private let listPadding: CGFloat = 12
private let fileSpacing: CGFloat = 10
private let fileHeaderPadding: CGFloat = 8
private let fileCornerRadius: CGFloat = 8
private let linePaddingHorizontal: CGFloat = 8
private let addedLineOpacity = 0.14
private let removedLineOpacity = 0.14
private let hunkHeaderOpacity = 0.08
private let reviewedSystemImage = "checkmark.circle.fill"
private let notReviewedSystemImage = "circle"
private let oversizeSystemImage = "doc.text.magnifyingglass"
private let bytesPerKilobyte = 1024
private let discardSystemImage = "arrow.uturn.backward.circle"

struct CommitDiffView: View {
    static let markReviewedHelp = "Mark as reviewed"
    static let markNotReviewedHelp = "Mark as not reviewed"
    static let noPreviewMessage = "No preview: binary, mode change, or past the untracked file limit."
    static let cannotDiscardHelp = "Renames, copies and conflicts cannot be discarded from here."

    let draft: CommitDraft
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: fileSpacing) {
                if draft.diff.isTruncated {
                    oversizeBanner
                }
                ForEach(draft.changes) { change in
                    fileSection(change)
                }
            }
            .padding(listPadding)
        }
    }

    private var oversizeBanner: some View {
        let editor = environment.preferences.preferredEditor
        return BannerView(
            systemImage: oversizeSystemImage,
            title: "Diff too large to show here",
            message: "More than \(GitDiff.maxLines) lines or \(GitDiff.maxBytes / bytesPerKilobyte) KB. Review it in your editor.",
            actionTitle: ExternalAppActions.openTitle(editor),
            action: { environment.externalApps.open(draft.repository, in: editor) },
            actionDisabled: !environment.externalApps.isInstalled(editor)
        )
    }

    @ViewBuilder
    private func fileSection(_ change: GitChange) -> some View {
        let reviewed = draft.isReviewed(change.path)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        environment.commits.toggleReviewed(change.path)
                    } label: {
                        Image(systemName: reviewed ? reviewedSystemImage : notReviewedSystemImage)
                    }
                    .buttonStyle(.plain)
                    .help(reviewed ? Self.markNotReviewedHelp : Self.markReviewedHelp)
                    StatusBadge(systemImage: Self.symbol(for: change.kind), text: change.kind.label, tint: Self.tint(for: change.kind))
                    Text(change.path)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .contentShape(Rectangle())
                .onTapGesture { environment.commits.toggleReviewed(change.path) }
                Spacer()
                Button {
                    environment.commits.requestDiscard(change)
                } label: {
                    Image(systemName: discardSystemImage)
                }
                .buttonStyle(.plain)
                .help(change.kind.canDiscard ? CommitActions.discardTitle : Self.cannotDiscardHelp)
                .disabled(!change.kind.canDiscard || environment.commits.isBusy || environment.commits.isCommitted)
            }
            .padding(fileHeaderPadding)
            .background(.quaternary)
            .foregroundStyle(reviewed ? .secondary : .primary)

            if !reviewed && !draft.diff.isTruncated {
                if let file = draft.diff.files.first(where: { $0.path == change.path }) {
                    DiffBodyView(lines: DiffLines.body(of: file.text))
                } else {
                    Text(Self.noPreviewMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(fileHeaderPadding)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: fileCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: fileCornerRadius, style: .continuous)
                .strokeBorder(.separator)
        )
    }

    private enum KindSymbol {
        static let added = "plus.circle"
        static let modified = "pencil.circle"
        static let deleted = "minus.circle"
        static let renamed = "arrow.right.circle"
        static let conflicted = "exclamationmark.triangle"
        static let other = "circle"
    }

    private static func symbol(for kind: GitChange.Kind) -> String {
        switch kind {
        case .untracked, .added: KindSymbol.added
        case .modified: KindSymbol.modified
        case .deleted: KindSymbol.deleted
        case .renamed, .copied: KindSymbol.renamed
        case .conflicted: KindSymbol.conflicted
        case .other: KindSymbol.other
        }
    }

    private static func tint(for kind: GitChange.Kind) -> Color {
        switch kind {
        case .untracked, .added: .green
        case .modified: .orange
        case .deleted: .red
        case .renamed, .copied: .secondary
        case .conflicted: .red
        case .other: .secondary
        }
    }
}

/// Line prefixes git uses; checked with `hasPrefix`, so the three-character headers must be
/// tested before their one-character cousins.
enum DiffLines {
    static let newPathHeader = "+++ "
    static let oldPathHeader = "--- "
    static let added = "+"
    static let removed = "-"
    static let hunkHeader = "@@"

    enum Role: Equatable { case added, removed, hunkHeader, context }

    /// Drops everything up to and including the `+++` line: the file header repeats what the
    /// row above already shows. A diff without one (pure rename, binary) is shown whole.
    static func body(of fileDiff: String) -> [String] {
        var lines = fileDiff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let headerEnd = lines.firstIndex(where: { $0.hasPrefix(newPathHeader) }) else {
            if lines.last == "" {
                lines.removeLast()
            }
            return lines
        }
        var body = Array(lines[(headerEnd + 1)...])
        if body.last == "" {
            body.removeLast()
        }
        return body
    }

    static func role(of line: String) -> Role {
        if line.hasPrefix(hunkHeader) { return .hunkHeader }
        if line.hasPrefix(newPathHeader) || line.hasPrefix(oldPathHeader) { return .context }
        if line.hasPrefix(added) { return .added }
        if line.hasPrefix(removed) { return .removed }
        return .context
    }
}

private struct DiffBodyView: View {
    let lines: [String]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(lines.indices, id: \.self) { index in
                Text(lines[index])
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, linePaddingHorizontal)
                    .background(background(for: lines[index]))
                    .foregroundStyle(foreground(for: lines[index]))
            }
        }
        .textSelection(.enabled)
    }

    private func background(for line: String) -> Color {
        switch DiffLines.role(of: line) {
        case .added: .green.opacity(addedLineOpacity)
        case .removed: .red.opacity(removedLineOpacity)
        case .hunkHeader: .blue.opacity(hunkHeaderOpacity)
        case .context: .clear
        }
    }

    private func foreground(for line: String) -> Color {
        DiffLines.role(of: line) == .hunkHeader ? .secondary : .primary
    }
}
