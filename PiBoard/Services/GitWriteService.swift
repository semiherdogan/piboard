import Foundation

/// Mutations behind the commit sheet. Push is absent on purpose: it can prompt for a passphrase,
/// so it runs through `GitTerminalRunning` where the user can answer.
protocol GitWriting: Sendable {
    func stageAll(at path: URL) async throws
    func commit(message: String, at path: URL) async throws
    /// Nil when the current branch tracks nothing yet, so the first push has to set the upstream.
    func upstream(at path: URL) async throws -> String?
    /// Returns the file to its HEAD state, or deletes it when HEAD never had it.
    func discard(_ change: GitChange, at path: URL) async throws
}

final class GitWriteService: GitWriting {
    /// Hooks run inside `commit`, so it gets more time than a status read.
    static let commitTimeout: TimeInterval = 60

    private let runner: GitCommandRunner

    init(runner: GitCommandRunner = GitCommandRunner(timeout: commitTimeout)) {
        self.runner = runner
    }

    func stageAll(at path: URL) async throws {
        _ = try await runner.runChecked(GitArguments.addAll, in: path)
    }

    func commit(message: String, at path: URL) async throws {
        _ = try await runner.runChecked(GitArguments.commitWithMessage + [message], in: path)
    }

    func upstream(at path: URL) async throws -> String? {
        let result = try await runner.run(GitArguments.upstreamRef, in: path)
        guard result.exitCode == 0 else {
            if result.stderr.contains(GitCommandRunner.notARepositoryMarker) {
                throw GitServiceError.notARepository
            }
            return nil
        }
        let upstream = result.output
        return upstream.isEmpty ? nil : upstream
    }

    func discard(_ change: GitChange, at path: URL) async throws {
        switch change.kind {
        case .untracked:
            _ = try await runner.runChecked(GitArguments.cleanForced + [change.path], in: path)
        case .added:
            // Staged but new in HEAD: restore cannot bring back nothing, so unstage then remove.
            _ = try await runner.runChecked(GitArguments.restoreStagedOnly + [change.path], in: path)
            _ = try await runner.runChecked(GitArguments.cleanForced + [change.path], in: path)
        case .modified, .deleted, .other:
            _ = try await runner.runChecked(GitArguments.restoreToHead + [change.path], in: path)
        case .renamed, .copied, .conflicted:
            throw GitWriteError.cannotDiscard(change.kind)
        }
    }
}

enum GitWriteError: Error, Equatable, LocalizedError {
    case cannotDiscard(GitChange.Kind)

    var errorDescription: String? {
        switch self {
        case .cannotDiscard(let kind): "\(kind.label) changes cannot be discarded from here."
        }
    }
}

/// Argument builder kept apart from the runner so the interactive and silent paths share it.
enum GitPushCommand {
    /// The first push of a branch sets `origin` as upstream so later pushes need no arguments.
    /// A clone without `origin` fails in git's own words inside the console the user is watching.
    static func arguments(branch: String, hasUpstream: Bool) -> [String] {
        guard !hasUpstream else { return GitArguments.push }
        return GitArguments.push + [GitArguments.setUpstreamFlag, GitArguments.defaultRemoteName, branch]
    }
}
