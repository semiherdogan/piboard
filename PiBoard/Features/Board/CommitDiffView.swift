import SwiftUI

private let listPadding: CGFloat = 12
private let fileSpacing: CGFloat = 10
private let fileHeaderPadding: CGFloat = 8
private let fileCornerRadius: CGFloat = 8
private let linePaddingHorizontal: CGFloat = 8
private let addedLineOpacity = 0.14
private let removedLineOpacity = 0.14
private let hunkHeaderOpacity = 0.08
private let stagedSystemImage = "checkmark.circle.fill"
private let unstagedSystemImage = "circle"
private let partiallyStagedSystemImage = "circle.lefthalf.filled"
private let oversizeSystemImage = "doc.text.magnifyingglass"
private let bytesPerMegabyte = 1024 * 1024
private let discardSystemImage = "arrow.uturn.backward.circle"

struct CommitDiffView: View {
    static let stageHelp = "Stage (git add)"
    static let unstageHelp = "Unstage"
    static let restageHelp = "Changed since staged. Stage again"
    static let modifiedSinceStagedLabel = "Modified since staged"
    static let noPreviewMessage = "No preview: binary, mode change, or past the untracked file limit."
    static let cannotDiscardHelp = "Renames, copies and conflicts cannot be discarded from here."
    static let oversizeTitle = "Diff too large to show in full"
    /// Above this a file is folded until asked for; every diff line is its own view.
    static let foldedLineThreshold = 1_000
    /// Above this the file is never rendered inline; the editor is the right tool.
    static let inlineLineLimit = 20_000
    static let showLinesFormat = "Show %d lines"
    static let tooLargeInlineMessage = "Too large to show here."

    let changes: ChangeSetModel
    @Environment(AppEnvironment.self) private var environment
    @State private var expandedPaths: Set<String> = []

    var body: some View {
        if let changeSet = changes.changeSet {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: fileSpacing) {
                    if changeSet.diff.omittedFileCount > 0 {
                        oversizeBanner(repository: changeSet.repository, omittedFileCount: changeSet.diff.omittedFileCount)
                    }
                    ForEach(changeSet.changes) { change in
                        fileSection(change, in: changeSet)
                    }
                }
                .padding(listPadding)
            }
        }
    }

    private func oversizeBanner(repository: URL, omittedFileCount: Int) -> some View {
        let editor = environment.preferences.preferredEditor
        return BannerView(
            systemImage: oversizeSystemImage,
            title: Self.oversizeTitle,
            message: "\(omittedFileCount) file(s) past the \(GitDiff.maxBytes / bytesPerMegabyte) MB limit are not shown. Review them in your editor.",
            actionTitle: ExternalAppActions.openTitle(editor),
            action: { environment.externalApps.open(repository, in: editor) },
            actionDisabled: !environment.externalApps.isInstalled(editor)
        )
    }

    @ViewBuilder
    private func fileSection(_ change: GitChange, in changeSet: ChangeSet) -> some View {
        let staging = changeSet.staging(of: change.path)
        let isIndexBusy = !changes.canMutate
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        changes.toggleStaged(change)
                    } label: {
                        Image(systemName: Self.systemImage(for: staging))
                    }
                    .buttonStyle(.plain)
                    .help(Self.help(for: staging))
                    .disabled(isIndexBusy)
                    StatusBadge(systemImage: Self.symbol(for: change.kind), text: change.kind.label, tint: Self.tint(for: change.kind))
                    Text(change.path)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if staging == .partiallyStaged {
                        StatusBadge(systemImage: partiallyStagedSystemImage, text: Self.modifiedSinceStagedLabel, tint: .orange)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isIndexBusy else { return }
                    changes.toggleStaged(change)
                }
                Spacer()
                Button {
                    changes.requestDiscard(change)
                } label: {
                    Image(systemName: discardSystemImage)
                }
                .buttonStyle(.plain)
                .help(change.kind.canDiscard ? ChangeSetModel.discardTitle : Self.cannotDiscardHelp)
                .disabled(!change.kind.canDiscard || isIndexBusy)
            }
            .padding(fileHeaderPadding)
            .background(.quaternary)
            .foregroundStyle(staging == .staged ? .secondary : .primary)

            if staging != .staged {
                if let file = changeSet.diff.files.first(where: { $0.path == change.path }) {
                    fileBody(file, change: change, repository: changeSet.repository)
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

    @ViewBuilder
    private func fileBody(_ file: GitFileDiff, change: GitChange, repository: URL) -> some View {
        if file.lineCount > Self.inlineLineLimit {
            let editor = environment.preferences.preferredEditor
            HStack {
                Text(Self.tooLargeInlineMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(ExternalAppActions.openTitle(editor)) {
                    environment.externalApps.open(repository.appendingPathComponent(change.path), in: editor)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .disabled(!environment.externalApps.isInstalled(editor))
            }
            .padding(fileHeaderPadding)
        } else if file.lineCount > Self.foldedLineThreshold && !expandedPaths.contains(change.path) {
            Button(String(format: Self.showLinesFormat, file.lineCount)) {
                expandedPaths.insert(change.path)
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .padding(fileHeaderPadding)
        } else {
            DiffBodyView(lines: DiffLines.body(of: file.text))
        }
    }

    private static func systemImage(for staging: GitChange.Staging) -> String {
        switch staging {
        case .staged: stagedSystemImage
        case .unstaged: unstagedSystemImage
        case .partiallyStaged: partiallyStagedSystemImage
        }
    }

    private static func help(for staging: GitChange.Staging) -> String {
        switch staging {
        case .staged: unstageHelp
        case .unstaged: stageHelp
        case .partiallyStaged: restageHelp
        }
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
