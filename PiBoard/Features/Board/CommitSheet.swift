import SwiftUI

private let sheetWidth: CGFloat = 760
private let sheetHeight: CGFloat = 620
private let sheetPadding: CGFloat = 16
private let messageEditorMinHeight: CGFloat = 90
private let messageEditorMaxHeight: CGFloat = 140
private let messageHeaderSpacing: CGFloat = 6
private let branchSystemImage = "arrow.triangle.branch"
private let generateSystemImage = "sparkles"
private let errorSystemImage = "exclamationmark.triangle"
private let cleanTreeSystemImage = "checkmark.circle"
private let detachedHeadLabel = "detached HEAD"

struct CommitSheet: View {
    static let generateHelp = "Generate a message with Pi. The diff is sent to the model provider."
    static let detachedHeadHelp = "There is no branch to push from a detached HEAD."
    static let cancelTitle = "Cancel"
    static let cancelPushTitle = "Cancel Push"
    static let closeTitle = "Close"
    static let messageTitle = "Message"
    static let generateTitle = "Generate with Pi"

    let request: CommitRequest
    @Environment(AppEnvironment.self) private var environment

    private var commits: CommitActions { environment.commits }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(sheetPadding)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
                .padding(sheetPadding)
        }
        .frame(width: sheetWidth, height: sheetHeight)
        .confirmationDialog(
            commits.discardRequest?.title ?? "",
            isPresented: discardBinding,
            presenting: commits.discardRequest
        ) { _ in
            Button(CommitActions.discardTitle, role: .destructive) {
                commits.confirmDiscard()
            }
            Button(Self.cancelTitle, role: .cancel) {
                commits.cancelDiscard()
            }
        } message: { request in
            Text(request.message)
        }
    }

    private var discardBinding: Binding<Bool> {
        Binding(
            get: { commits.discardRequest != nil },
            set: { isPresented in
                if !isPresented {
                    commits.cancelDiscard()
                }
            }
        )
    }

    private var header: some View {
        HStack {
            Text("Commit")
                .font(.headline)
            Text(request.title)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if let draft = commits.draft {
                Label(draft.branch ?? detachedHeadLabel, systemImage: branchSystemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(changeCountText(draft.changes.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(draft.reviewedCount)/\(draft.changes.count) reviewed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func changeCountText(_ count: Int) -> String {
        count == 1 ? "1 change" : "\(count) changes"
    }

    @ViewBuilder
    private var content: some View {
        if let pushRun = commits.pushRun {
            VStack(alignment: .leading, spacing: 0) {
                Label("git push", systemImage: "terminal")
                    .padding(sheetPadding)
                TerminalHostView(taskID: request.id, session: pushRun.session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if commits.draft == nil && commits.phase == .loading {
            ProgressView("Reading changes...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let draft = commits.draft, draft.changes.isEmpty {
            ContentUnavailableView("Nothing to Commit", systemImage: cleanTreeSystemImage, description: Text("The working tree is clean."))
        } else if let draft = commits.draft {
            CommitDiffView(draft: draft)
        } else {
            ContentUnavailableView("Could Not Read Changes", systemImage: errorSystemImage)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let lastError = commits.lastError {
                Label(lastError, systemImage: errorSystemImage)
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .textSelection(.enabled)
            }
            VStack(alignment: .leading, spacing: messageHeaderSpacing) {
                HStack {
                    Text(Self.messageTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    generateButton
                }
                PromptEditor(text: messageBinding, minHeight: messageEditorMinHeight)
                    .frame(maxHeight: messageEditorMaxHeight)
                    .disabled(!canEditMessage)
            }
            buttonsRow
        }
    }

    private var generateButton: some View {
        Button {
            commits.generateMessage()
        } label: {
            if commits.phase == .generating {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label(Self.generateTitle, systemImage: generateSystemImage)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(Self.generateHelp)
        .disabled(!canEditMessage)
    }

    @ViewBuilder
    private var buttonsRow: some View {
        HStack {
            switch commits.phase {
            case .committing:
                ProgressView().controlSize(.small)
                Text("Committing...")
            case .pushing:
                ProgressView().controlSize(.small)
                Text("Pushing...")
            case .discarding:
                ProgressView().controlSize(.small)
                Text("Discarding...")
            case .loading, .editing, .generating:
                EmptyView()
            }
            Spacer()
            Button(dismissTitle) {
                commits.dismiss()
            }
            .disabled(commits.phase == .committing || commits.phase == .discarding)
            if !commits.isCommitted {
                Button(CommitActions.commitTitle) {
                    commits.commit(andPush: false)
                }
                .disabled(!canCommit)
                Button(CommitActions.commitAndPushTitle) {
                    commits.commit(andPush: true)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCommit || !commits.canPush)
                .help(commits.canPush ? "" : Self.detachedHeadHelp)
            }
            if commits.isCommitted && commits.phase == .editing {
                Button(CommitActions.retryPushTitle) {
                    commits.retryPush()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!commits.canPush)
            }
        }
    }

    private var dismissTitle: String {
        if commits.phase == .pushing {
            return Self.cancelPushTitle
        }
        if commits.isCommitted {
            return Self.closeTitle
        }
        return Self.cancelTitle
    }

    private var canEditMessage: Bool {
        (commits.draft.map { !$0.changes.isEmpty } ?? false) && !commits.isCommitted && !commits.isBusy
    }

    private var canCommit: Bool {
        (commits.draft?.canCommit ?? false) && !commits.isBusy
    }

    private var messageBinding: Binding<String> {
        Binding(
            get: { commits.message },
            set: { commits.setMessage($0) }
        )
    }
}
