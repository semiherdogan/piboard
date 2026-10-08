import Foundation
import Observation

/// What the sheet was opened for; `title` names the task or project it came from.
struct CommitRequest: Identifiable, Equatable {
    let id = UUID()
    let path: URL
    let title: String
}

@MainActor
@Observable
final class CommitActions {
    nonisolated static let menuTitle = "Commit..."
    nonisolated static let commitTitle = "Commit"
    nonisolated static let commitAndPushTitle = "Commit & Push"
    nonisolated static let retryPushTitle = "Retry Push"
    nonisolated static let detachedHeadMessage = "Committed. HEAD is detached, so there is no branch to push."
    private static let successExitCode: Int32 = 0

    enum Phase: Equatable {
        case idle
        case editing
        case generating
        case committing
        case pushing
    }

    // Presented by MainWindow as a sheet; nil closes it.
    private(set) var request: CommitRequest?
    private(set) var message = ""
    private(set) var phase: Phase = .idle
    /// Shown inside the sheet; a push error is long, so it never goes to `board.lastError`.
    private(set) var lastError: String?
    /// Set once the commit landed, so a failed push is retried without committing again.
    private(set) var isCommitted = false
    /// Kept after a failed push so the console with git's message stays visible.
    private(set) var pushRun: GitTerminalRun?
    // Bumped after each commit so the board git row refreshes.
    private(set) var revision = 0
    // Exposed so tests can await completion.
    private(set) var actionTask: Task<Void, Never>?

    let changes: ChangeSetModel
    private let git: GitServicing
    private let writer: GitWriting
    private let terminal: any GitTerminalRunning
    private let generator: any CommitMessageGenerating

    init(changes: ChangeSetModel, git: GitServicing, terminal: any GitTerminalRunning, generator: any CommitMessageGenerating, writer: GitWriting) {
        self.changes = changes
        self.git = git
        self.writer = writer
        self.terminal = terminal
        self.generator = generator
    }

    var draft: CommitDraft? { changes.changeSet.map { CommitDraft(changeSet: $0, message: message) } }

    var isBusy: Bool {
        switch phase {
        case .generating, .committing, .pushing: true
        case .idle, .editing: changes.isBusy
        }
    }

    var canPush: Bool { changes.changeSet?.branch != nil }

    func begin(path: URL, title: String) {
        actionTask?.cancel()
        message = ""
        lastError = nil
        isCommitted = false
        pushRun = nil
        changes.isLocked = false
        changes.load(path: path)
        request = CommitRequest(path: path, title: title)
        phase = .editing
    }

    func dismiss() {
        actionTask?.cancel()
        if pushRun?.session.state.isRunning == true {
            pushRun?.session.terminate()
        }
        pushRun = nil
        request = nil
        message = ""
        lastError = nil
        isCommitted = false
        phase = .idle
        changes.reset()
    }

    func setMessage(_ text: String) {
        message = text
    }

    func generateMessage() {
        guard let draft, phase == .editing, !changes.isBusy else { return }
        let requestID = request?.id
        lastError = nil
        phase = .generating
        actionTask = Task {
            // A missing log is a weaker prompt, not a failure.
            let subjects: [String]
            do {
                subjects = try await self.git.recentSubjects(limit: PromptDiffBudget.maxSubjects, at: draft.changeSet.repository)
            } catch {
                subjects = []
            }
            guard self.request?.id == requestID else { return }
            do {
                let context = CommitPromptContext(
                    diff: PromptDiffBudget.render(diff: draft.changeSet.diff, changes: draft.changeSet.changes),
                    branch: draft.changeSet.branch,
                    recentSubjects: PromptDiffBudget.subjects(subjects)
                )
                let message = try await self.generator.generate(context)
                guard self.request?.id == requestID else { return }
                self.message = message
            } catch is CancellationError {
                return
            } catch {
                guard self.request?.id == requestID else { return }
                self.lastError = "Could not generate a message: \(error.localizedDescription)"
            }
            self.phase = .editing
        }
    }

    func commit(andPush: Bool) {
        guard let draft, draft.canCommit, phase == .editing, !isCommitted, !changes.isBusy else { return }
        let request = request
        lastError = nil
        phase = .committing
        // Locked from the start so the index is not edited while the commit runs.
        changes.isLocked = true
        actionTask = Task {
            do {
                try await self.writer.commit(message: draft.trimmedMessage, at: draft.changeSet.repository)
            } catch {
                guard self.request?.id == request?.id else { return }
                self.lastError = "Could not commit: \(error.localizedDescription)"
                self.changes.isLocked = false
                self.phase = .editing
                return
            }
            guard self.request?.id == request?.id else { return }
            self.isCommitted = true
            self.revision += 1
            Diagnostics.git.info("commit path=\(draft.changeSet.repository.path, privacy: .public) push=\(andPush, privacy: .public)")
            if andPush {
                await self.push(draft)
            } else {
                self.dismiss()
            }
        }
    }

    private func push(_ draft: CommitDraft) async {
        guard let branch = draft.changeSet.branch else {
            lastError = Self.detachedHeadMessage
            phase = .editing
            return
        }
        let requestID = request?.id
        phase = .pushing
        let hasUpstream: Bool
        do {
            hasUpstream = try await writer.upstream(at: draft.changeSet.repository) != nil
        } catch {
            guard request?.id == requestID else { return }
            lastError = "Could not read the upstream: \(error.localizedDescription)"
            phase = .editing
            return
        }
        guard request?.id == requestID else { return }
        let run = terminal.start(GitPushCommand.arguments(branch: branch, hasUpstream: hasUpstream), in: draft.changeSet.repository)
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
}
