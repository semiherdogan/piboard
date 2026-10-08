import Foundation
import Observation

/// What the sheet was opened for; `title` names the task or project it came from.
struct CommitRequest: Identifiable, Equatable {
    let id = UUID()
    let path: URL
    let title: String
}

/// Confirmed by the sheet before `CommitActions.confirmDiscard` runs it.
struct DiscardRequest: Equatable {
    let change: GitChange

    var title: String { "Discard changes to \(change.path)?" }

    var message: String {
        switch change.kind {
        case .untracked, .added: "The file will be deleted. This cannot be undone."
        case .modified, .deleted, .other: "The file goes back to its last committed state. This cannot be undone."
        case .renamed, .copied, .conflicted: ""
        }
    }
}

@MainActor
@Observable
final class CommitActions {
    nonisolated static let menuTitle = "Commit..."
    nonisolated static let commitTitle = "Commit"
    nonisolated static let commitAndPushTitle = "Commit & Push"
    nonisolated static let retryPushTitle = "Retry Push"
    nonisolated static let discardTitle = "Discard Changes"
    nonisolated static let discardMenuTitle = "Discard Changes..."
    nonisolated static let notARepositoryMessage = "Not a Git repository."
    nonisolated static let detachedHeadMessage = "Committed. HEAD is detached, so there is no branch to push."
    /// Reading untracked files from disk is bounded; the rest are listed without a preview.
    nonisolated static let maxUntrackedPreviews = 50
    private static let successExitCode: Int32 = 0

    enum Phase: Equatable {
        case loading
        case editing
        case generating
        case committing
        case pushing
        case discarding
    }

    // Presented by MainWindow as a sheet; nil closes it.
    private(set) var request: CommitRequest?
    private(set) var draft: CommitDraft?
    private(set) var phase: Phase = .loading
    /// Shown inside the sheet; a push error is long, so it never goes to `board.lastError`.
    private(set) var lastError: String?
    /// Set once the commit landed, so a failed push is retried without committing again.
    private(set) var isCommitted = false
    /// Kept after a failed push so the console with git's message stays visible.
    private(set) var pushRun: GitTerminalRun?
    private(set) var discardRequest: DiscardRequest?
    // Bumped after each commit so the board git row refreshes.
    private(set) var revision = 0
    // Exposed so tests can await completion.
    private(set) var actionTask: Task<Void, Never>?

    private let git: GitServicing
    private let writer: GitWriting
    private let terminal: any GitTerminalRunning
    private let generator: any CommitMessageGenerating

    init(git: GitServicing, writer: GitWriting, terminal: any GitTerminalRunning, generator: any CommitMessageGenerating) {
        self.git = git
        self.writer = writer
        self.terminal = terminal
        self.generator = generator
    }

    var message: String { draft?.message ?? "" }

    var isBusy: Bool {
        switch phase {
        case .loading, .generating, .committing, .pushing, .discarding: true
        case .editing: false
        }
    }

    var canPush: Bool { draft?.branch != nil }

    func begin(path: URL, title: String) {
        draft = nil
        lastError = nil
        isCommitted = false
        pushRun = nil
        discardRequest = nil
        phase = .loading
        let request = CommitRequest(path: path, title: title)
        self.request = request
        actionTask = Task { await self.load(request) }
    }

    func dismiss() {
        if pushRun?.session.state.isRunning == true {
            pushRun?.session.terminate()
        }
        pushRun = nil
        discardRequest = nil
        request = nil
        draft = nil
        lastError = nil
        isCommitted = false
        phase = .loading
    }

    func setMessage(_ text: String) {
        draft?.message = text
    }

    func toggleReviewed(_ path: String) {
        draft?.toggleReviewed(path)
    }

    func generateMessage() {
        guard let draft, phase == .editing else { return }
        let requestID = request?.id
        lastError = nil
        phase = .generating
        actionTask = Task {
            // A missing log is a weaker prompt, not a failure.
            let subjects: [String]
            do {
                subjects = try await self.git.recentSubjects(limit: PromptDiffBudget.maxSubjects, at: draft.repository)
            } catch {
                subjects = []
            }
            guard self.request?.id == requestID else { return }
            do {
                let context = CommitPromptContext(
                    diff: PromptDiffBudget.render(diff: draft.diff, changes: draft.changes),
                    branch: draft.branch,
                    recentSubjects: PromptDiffBudget.subjects(subjects)
                )
                let message = try await self.generator.generate(context)
                guard self.request?.id == requestID else { return }
                self.draft?.message = message
            } catch {
                guard self.request?.id == requestID else { return }
                self.lastError = "Could not generate a message: \(error.localizedDescription)"
            }
            self.phase = .editing
        }
    }

    func commit(andPush: Bool) {
        guard let draft, draft.canCommit, phase == .editing, !isCommitted else { return }
        let request = request
        lastError = nil
        phase = .committing
        actionTask = Task {
            do {
                try await self.writer.stageAll(at: draft.repository)
                try await self.writer.commit(message: draft.trimmedMessage, at: draft.repository)
            } catch {
                guard self.request?.id == request?.id else { return }
                self.lastError = "Could not commit: \(error.localizedDescription)"
                self.phase = .editing
                return
            }
            guard self.request?.id == request?.id else { return }
            self.isCommitted = true
            self.revision += 1
            Diagnostics.git.info("commit path=\(draft.repository.path, privacy: .public) push=\(andPush, privacy: .public)")
            if andPush {
                await self.push(draft)
            } else {
                self.dismiss()
            }
        }
    }

    private func push(_ draft: CommitDraft) async {
        guard let branch = draft.branch else {
            lastError = Self.detachedHeadMessage
            phase = .editing
            return
        }
        let requestID = request?.id
        phase = .pushing
        let hasUpstream: Bool
        do {
            hasUpstream = try await writer.upstream(at: draft.repository) != nil
        } catch {
            guard request?.id == requestID else { return }
            lastError = "Could not read the upstream: \(error.localizedDescription)"
            phase = .editing
            return
        }
        guard request?.id == requestID else { return }
        let run = terminal.start(GitPushCommand.arguments(branch: branch, hasUpstream: hasUpstream), in: draft.repository)
        pushRun = run
        let outcome = await run.outcome.value
        // A dismiss or retry in the meantime replaced the run; its result belongs to nobody.
        guard pushRun?.session === run.session else { return }
        switch outcome {
        case .exited(Self.successExitCode):
            dismiss()
        case .exited(let code):
            lastError = "Push exited with code \(code.map(String.init) ?? "unknown")."
            phase = .editing
        case .timedOut:
            lastError = "Push timed out after \(Int(GitTerminalRunner.defaultTimeout.components.seconds)) seconds."
            phase = .editing
        }
    }

    func retryPush() {
        guard let draft, isCommitted, phase == .editing else { return }
        lastError = nil
        actionTask = Task { await self.push(draft) }
    }

    func requestDiscard(_ change: GitChange) {
        guard phase == .editing, !isCommitted, change.kind.canDiscard else { return }
        discardRequest = DiscardRequest(change: change)
    }

    func cancelDiscard() {
        discardRequest = nil
    }

    func confirmDiscard() {
        guard let request = discardRequest, let draft, phase == .editing else { return }
        discardRequest = nil
        let requestID = self.request?.id
        lastError = nil
        phase = .discarding
        actionTask = Task {
            do {
                try await self.writer.discard(request.change, at: draft.repository)
            } catch {
                guard self.request?.id == requestID else { return }
                self.lastError = "Could not discard \(request.change.path): \(error.localizedDescription)"
                self.phase = .editing
                return
            }
            guard self.request?.id == requestID, let current = self.request else { return }
            self.revision += 1
            Diagnostics.git.info("discard path=\(draft.repository.path, privacy: .public)")
            await self.load(current, keeping: draft)
        }
    }

    private func load(_ request: CommitRequest, keeping previous: CommitDraft? = nil) async {
        let info: RepositoryInfo
        do {
            info = try await git.repositoryInfo(at: request.path)
        } catch GitServiceError.notARepository {
            lastError = Self.notARepositoryMessage
            phase = .editing
            return
        } catch {
            lastError = "Could not read the repository: \(error.localizedDescription)"
            phase = .editing
            return
        }
        guard info.isRepository else {
            lastError = Self.notARepositoryMessage
            phase = .editing
            return
        }
        let changes: [GitChange]
        let unified: String
        do {
            changes = try await git.status(at: request.path)
            unified = try await git.diff(at: request.path)
        } catch {
            lastError = "Could not read the repository: \(error.localizedDescription)"
            phase = .editing
            return
        }
        let root = info.topLevel ?? request.path
        let untrackedPaths = changes.filter { $0.kind == .untracked }.prefix(Self.maxUntrackedPreviews).map(\.path)
        let untracked = await Task.detached(priority: .userInitiated) {
            untrackedPaths.map { UntrackedFile.read(path: $0, in: root) }
        }.value
        guard self.request?.id == request.id else { return }
        var newDraft = CommitDraft(repository: request.path, branch: info.headBranch, changes: changes, diff: GitDiff.make(unified: unified, untracked: untracked))
        newDraft.message = previous?.message ?? ""
        newDraft.reviewedPaths = (previous?.reviewedPaths ?? []).intersection(Set(changes.map(\.path)))
        draft = newDraft
        phase = .editing
    }
}
