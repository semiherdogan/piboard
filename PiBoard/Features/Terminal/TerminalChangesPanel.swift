import SwiftUI

private let panelMinWidth: CGFloat = 320
private let panelIdealWidth: CGFloat = 440
private let headerPadding: CGFloat = 10
private let refreshSystemImage = "arrow.clockwise"
private let branchSystemImage = "arrow.triangle.branch"
private let cleanSystemImage = "checkmark.circle"
private let errorSystemImage = "exclamationmark.triangle"
private let detachedHeadLabel = "detached HEAD"

struct TerminalChangesPanel: View {
    static let title = "Changes"
    static let cleanMessage = "Working tree is clean."
    static let commitTitle = "Commit..."
    static let cancelTitle = "Cancel"
    static let loadingTitle = "Reading changes..."
    static let refreshHelp = "Refresh Changes"

    let path: URL
    let taskID: UUID
    let title: String
    @Environment(AppEnvironment.self) private var environment
    @State private var changes: ChangeSetModel?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            if let error = changes?.lastError {
                Divider()
                Label(error, systemImage: errorSystemImage)
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .textSelection(.enabled)
                    .padding(headerPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: panelMinWidth, idealWidth: panelIdealWidth)
        .confirmationDialog(
            changes?.discardRequest?.title ?? "",
            isPresented: discardBinding,
            presenting: changes?.discardRequest
        ) { _ in
            Button(ChangeSetModel.discardTitle, role: .destructive) {
                changes?.confirmDiscard()
            }
            Button(Self.cancelTitle, role: .cancel) {
                changes?.cancelDiscard()
            }
        } message: { request in
            Text(request.message)
        }
        .onAppear { start() }
        .onChange(of: path) { start() }
        .onChange(of: environment.settleRevision) {
            if environment.lastSettledTaskID == taskID {
                changes?.reload()
            }
        }
        .onChange(of: environment.commits.revision) { changes?.reload() }
        .onChange(of: environment.processes.runtimeState(for: taskID)) { changes?.reload() }
    }

    private var discardBinding: Binding<Bool> {
        Binding(
            get: { changes?.discardRequest != nil },
            set: { isPresented in
                if !isPresented {
                    changes?.cancelDiscard()
                }
            }
        )
    }

    private var header: some View {
        HStack {
            Text(Self.title)
                .font(.headline)
            if let changeSet = changes?.changeSet {
                Label(changeSet.branch ?? detachedHeadLabel, systemImage: branchSystemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(changeSet.stagedCount)/\(changeSet.changes.count) staged")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                changes?.reload()
            } label: {
                Image(systemName: refreshSystemImage)
            }
            .buttonStyle(.plain)
            .disabled(changes?.isBusy ?? true)
            .help(Self.refreshHelp)
            Button(Self.commitTitle) {
                environment.commits.begin(path: path, title: title)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(changes?.changeSet?.changes.isEmpty ?? true)
        }
        .padding(headerPadding)
    }

    @ViewBuilder
    private var content: some View {
        if let changes {
            if changes.changeSet == nil && changes.phase == .loading {
                ProgressView(Self.loadingTitle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let changeSet = changes.changeSet, changeSet.changes.isEmpty {
                ContentUnavailableView(Self.cleanMessage, systemImage: cleanSystemImage)
            } else {
                CommitDiffView(changes: changes)
            }
        }
    }

    private func start() {
        let model = changes ?? environment.makeChangeSetModel()
        changes = model
        model.load(path: path)
    }
}
