import Foundation
import Observation

/// Confirmed by the view before `ChangeSetModel.confirmDiscard` runs it.
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
final class ChangeSetModel {
    nonisolated static let notARepositoryMessage = "Not a Git repository."
    nonisolated static let discardTitle = "Discard Changes"
    nonisolated static let stageAllTitle = "Stage All"
    /// Reading untracked files from disk is bounded; the rest are listed without a preview.
    nonisolated static let maxUntrackedPreviews = 50

    enum Phase: Equatable { case idle, loading, ready, staging, discarding }

    private(set) var path: URL?
    private(set) var changeSet: ChangeSet?
    private(set) var phase: Phase = .idle
    private(set) var lastError: String?
    private(set) var discardRequest: DiscardRequest?
    /// Set by the owner once a commit landed, so the index is not touched behind it.
    var isLocked = false
    // Bumped after a discard so the board git row refreshes.
    private(set) var revision = 0
    // Exposed so tests can await completion.
    private(set) var actionTask: Task<Void, Never>?
    /// Incremented per `load(path:)`; a result from an older load is dropped.
    private var generation = 0

    private let git: GitServicing
    private let writer: GitWriting

    init(git: GitServicing, writer: GitWriting) {
        self.git = git
        self.writer = writer
    }

    var isBusy: Bool {
        switch phase {
        case .loading, .staging, .discarding: true
        case .idle, .ready: false
        }
    }

    var canMutate: Bool { phase == .ready && !isLocked }

    /// Starts over for a path: clears the list and errors, then loads.
    func load(path: URL) {
        actionTask?.cancel()
        generation += 1
        self.path = path
        changeSet = nil
        lastError = nil
        discardRequest = nil
        phase = .loading
        startRead(path: path)
    }

    /// Re-reads the current path and keeps the list on screen while doing so.
    func reload() {
        // A staging or discard task ends with its own read, and replacing it would drop its error.
        guard let path, phase != .staging, phase != .discarding else { return }
        actionTask?.cancel()
        generation += 1
        lastError = nil
        phase = .loading
        startRead(path: path)
    }

    func reset() {
        actionTask?.cancel()
        actionTask = nil
        generation += 1
        path = nil
        changeSet = nil
        lastError = nil
        discardRequest = nil
        phase = .idle
    }

    /// Staging a file that is already fully staged does nothing; a partially staged one is re-added.
    func toggleStaged(_ change: GitChange) {
        guard canMutate, let changeSet, let path else { return }
        let generation = generation
        lastError = nil
        phase = .staging
        actionTask = Task {
            do {
                switch change.staging {
                case .unstaged, .partiallyStaged:
                    try await self.writer.stage(change.path, at: changeSet.repository)
                case .staged:
                    try await self.writer.unstage(change.path, at: changeSet.repository)
                }
            } catch {
                guard self.generation == generation else { return }
                self.lastError = "Could not update the index for \(change.path): \(error.localizedDescription)"
                self.phase = .ready
                return
            }
            guard self.generation == generation else { return }
            await self.read(path: path, generation: generation)
        }
    }

    func stageAll() {
        guard canMutate, let changeSet, let path else { return }
        let generation = generation
        lastError = nil
        phase = .staging
        actionTask = Task {
            do {
                try await self.writer.stageAll(at: changeSet.repository)
            } catch {
                guard self.generation == generation else { return }
                self.lastError = "Could not stage: \(error.localizedDescription)"
                self.phase = .ready
                return
            }
            guard self.generation == generation else { return }
            await self.read(path: path, generation: generation)
        }
    }

    func requestDiscard(_ change: GitChange) {
        guard canMutate, change.kind.canDiscard else { return }
        discardRequest = DiscardRequest(change: change)
    }

    func cancelDiscard() {
        discardRequest = nil
    }

    func confirmDiscard() {
        guard let request = discardRequest, canMutate, let changeSet, let path else { return }
        discardRequest = nil
        let generation = generation
        lastError = nil
        phase = .discarding
        actionTask = Task {
            do {
                try await self.writer.discard(request.change, at: changeSet.repository)
            } catch {
                guard self.generation == generation else { return }
                self.lastError = "Could not discard \(request.change.path): \(error.localizedDescription)"
                self.phase = .ready
                return
            }
            guard self.generation == generation else { return }
            self.revision += 1
            Diagnostics.git.info("discard path=\(changeSet.repository.path, privacy: .public)")
            await self.read(path: path, generation: generation)
        }
    }

    private func startRead(path: URL) {
        let generation = generation
        actionTask = Task { await self.read(path: path, generation: generation) }
    }

    private func read(path: URL, generation: Int) async {
        let info: RepositoryInfo
        do {
            info = try await git.repositoryInfo(at: path)
        } catch GitServiceError.notARepository {
            fail(Self.notARepositoryMessage, generation: generation)
            return
        } catch {
            fail("Could not read the repository: \(error.localizedDescription)", generation: generation)
            return
        }
        guard info.isRepository else {
            fail(Self.notARepositoryMessage, generation: generation)
            return
        }
        let changes: [GitChange]
        let unified: String
        do {
            changes = try await git.status(at: path)
            unified = try await git.diff(at: path)
        } catch {
            fail("Could not read the repository: \(error.localizedDescription)", generation: generation)
            return
        }
        let root = info.topLevel ?? path
        let untrackedPaths = changes.filter { $0.kind == .untracked }.prefix(Self.maxUntrackedPreviews).map(\.path)
        let untracked = await Task.detached(priority: .userInitiated) {
            untrackedPaths.map { UntrackedFile.read(path: $0, in: root) }
        }.value
        guard self.generation == generation else { return }
        changeSet = ChangeSet(repository: path, branch: info.headBranch, changes: changes, diff: GitDiff.make(unified: unified, untracked: untracked))
        phase = .ready
    }

    private func fail(_ message: String, generation: Int) {
        guard self.generation == generation else { return }
        lastError = message
        phase = .ready
    }
}
