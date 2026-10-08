import Foundation
import Synchronization

protocol GitServicing: Sendable {
    func repositoryInfo(at path: URL) async throws -> RepositoryInfo
    func status(at path: URL) async throws -> [GitChange]
    func currentBranch(at path: URL) async throws -> String?
    /// Nil when the repository has no remote to browse.
    func remoteBrowseURL(at path: URL) async throws -> URL?
    /// Working tree against HEAD: what `add --all` followed by a commit would record for tracked
    /// files. Untracked files are absent; callers read those from disk.
    func diff(at path: URL) async throws -> String
    /// Subjects of the newest commits, newest first; empty for a repository without commits.
    func recentSubjects(limit: Int, at path: URL) async throws -> [String]
}

struct RepositoryInfo: Sendable, Equatable {
    let isRepository: Bool
    let topLevel: URL?
    let headBranch: String?

    static let notARepository = RepositoryInfo(isRepository: false, topLevel: nil, headBranch: nil)
}

struct GitChange: Sendable, Equatable, Identifiable {
    /// Two-character porcelain v1 code, e.g. " M", "??", "R ".
    let status: String
    let path: String
    var id: String { path }
}

enum GitServiceError: Error, Equatable, LocalizedError {
    case notARepository
    case commandFailed(code: Int32, stderr: String)
    case timedOut
    case gitNotFound

    var errorDescription: String? {
        switch self {
        case .notARepository:
            "Not a Git repository."
        case .commandFailed(let code, let stderr):
            stderr.isEmpty ? "Git exited with code \(code)." : stderr
        case .timedOut:
            "Git did not respond in time."
        case .gitNotFound:
            "Git was not found at \(GitCommandRunner.defaultExecutable.path)."
        }
    }
}

enum GitArguments {
    static let isInsideWorkTree = ["rev-parse", "--is-inside-work-tree"]
    static let showTopLevel = ["rev-parse", "--show-toplevel"]
    static let abbreviatedHead = ["rev-parse", "--abbrev-ref", head]
    static let statusPorcelain = ["status", "--porcelain=v1", "-z"]
    // `-v` reports every remote with its URL in one call, so the name and the address do not
    // cost a process each.
    static let remotesVerbose = ["remote", "-v"]
    static let defaultRemoteName = "origin"
    static let fetchRemoteMarker = "(fetch)"
    static let worktreeAdd = ["worktree", "add"]
    static let worktreeRemove = ["worktree", "remove"]
    static let worktreePrune = ["worktree", "prune"]
    static let newBranchFlag = "-b"
    static let forceFlag = "--force"
    static let head = "HEAD"
    static let trueOutput = "true"
    // Porcelain -z paths are raw UTF-8; the diff must print the same bytes or files never match.
    static let unquotedPathsConfig = ["-c", "core.quotePath=false"]
    static let diffAgainstHead = unquotedPathsConfig + ["diff", head]
    // Only for a repository without commits, where HEAD does not resolve.
    static let diffWorkingTree = unquotedPathsConfig + ["diff"]
    static let addAll = ["add", "--all"]
    static let addPaths = ["add", "--"]
    static let commitWithMessage = ["commit", "-m"]
    static let upstreamRef = ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"]
    static let push = ["push"]
    static let setUpstreamFlag = "--set-upstream"
    static let logSubjects = ["log", "--format=%s"]
    static let maxCountFlag = "--max-count"
    static let restoreStagedOnly = ["restore", "--staged", "--"]
    // Resets both the index and the worktree, so a hunk the user staged by hand goes too.
    static let restoreToHead = ["restore", "--staged", "--worktree", "--"]
    // -d so an untracked directory listed as "dir/" goes with its contents.
    static let cleanForced = ["clean", "-fd", "--"]
}

struct GitCommandResult: Sendable {
    let exitCode: Int32
    let stdout: Data
    let stderr: String

    var output: String {
        String(decoding: stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Runs `/usr/bin/git -C <directory> ...` without blocking the caller's executor: pipe reads
/// and the exit wait happen on GCD threads and are bridged back through a continuation.
struct GitCommandRunner: Sendable {
    static let defaultExecutable = URL(fileURLWithPath: "/usr/bin/git")
    static let defaultTimeout: TimeInterval = 15
    private static let directoryFlag = "-C"
    private static let environmentOverrides = ["GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C"]
    static let notARepositoryMarker = "not a git repository"

    var executable = defaultExecutable
    var timeout = defaultTimeout
    /// Hooks and credential helpers are resolved through this PATH, so it must match a terminal's.
    var environment = LaunchEnvironment.shared.values

    /// Returns the result for any exit code; callers decide which codes are failures.
    func run(_ arguments: [String], in directory: URL) async throws -> GitCommandResult {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw GitServiceError.gitNotFound
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = [Self.directoryFlag, directory.path] + arguments
        process.environment = environment.merging(Self.environmentOverrides) { _, override in override }
        process.standardInput = FileHandle.nullDevice
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let state = RunState()
        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in group.leave() }

        do {
            try process.run()
        } catch {
            // A dispatch group released with outstanding enters traps.
            group.leave()
            throw GitServiceError.gitNotFound
        }
        // One slot each for stdout and stderr EOF.
        group.enter()
        group.enter()

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        let queue = DispatchQueue.global(qos: .userInitiated)
        queue.async {
            state.setStdout(stdoutHandle.readDataToEndOfFile())
            group.leave()
        }
        queue.async {
            state.setStderr(stderrHandle.readDataToEndOfFile())
            group.leave()
        }

        nonisolated(unsafe) let runningProcess = process
        let timeoutItem = DispatchWorkItem {
            guard runningProcess.isRunning else { return }
            state.markTimedOut()
            runningProcess.terminate()
        }
        queue.asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            group.notify(queue: queue) { continuation.resume() }
        }
        timeoutItem.cancel()

        let snapshot = state.snapshot()
        if snapshot.timedOut {
            throw GitServiceError.timedOut
        }
        return GitCommandResult(
            exitCode: process.terminationStatus,
            stdout: snapshot.stdout,
            stderr: String(decoding: snapshot.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Like `run`, but maps a non-zero exit to `notARepository` or `commandFailed`.
    func runChecked(_ arguments: [String], in directory: URL) async throws -> GitCommandResult {
        let result = try await run(arguments, in: directory)
        guard result.exitCode == 0 else {
            if result.stderr.contains(Self.notARepositoryMarker) {
                throw GitServiceError.notARepository
            }
            throw GitServiceError.commandFailed(code: result.exitCode, stderr: result.stderr)
        }
        return result
    }

    private final class RunState: Sendable {
        struct Snapshot {
            var stdout = Data()
            var stderr = Data()
            var timedOut = false
        }

        private let storage = Mutex(Snapshot())

        func setStdout(_ data: Data) { storage.withLock { $0.stdout = data } }
        func setStderr(_ data: Data) { storage.withLock { $0.stderr = data } }
        func markTimedOut() { storage.withLock { $0.timedOut = true } }
        func snapshot() -> Snapshot { storage.withLock { $0 } }
    }
}

final class GitService: GitServicing {
    private static let statusCodeLength = 2
    // Porcelain v1 status codes whose `-z` entry is followed by a second (original) path.
    private static let twoPathStatusCodes: Set<Character> = ["R", "C"]
    private static let entrySeparator: UInt8 = 0

    private let runner: GitCommandRunner

    init(runner: GitCommandRunner = GitCommandRunner()) {
        self.runner = runner
    }

    func repositoryInfo(at path: URL) async throws -> RepositoryInfo {
        let inside = try await runner.run(GitArguments.isInsideWorkTree, in: path)
        guard inside.exitCode == 0, inside.output == GitArguments.trueOutput else {
            return .notARepository
        }
        let topLevel = try await runner.runChecked(GitArguments.showTopLevel, in: path).output
        let branch = try await currentBranch(at: path)
        return RepositoryInfo(isRepository: true, topLevel: URL(fileURLWithPath: topLevel), headBranch: branch)
    }

    func status(at path: URL) async throws -> [GitChange] {
        let result = try await runner.runChecked(GitArguments.statusPorcelain, in: path)
        return Self.parsePorcelain(result.stdout)
    }

    /// Nil when HEAD is detached or unborn (a repository without commits).
    func currentBranch(at path: URL) async throws -> String? {
        let result = try await runner.run(GitArguments.abbreviatedHead, in: path)
        guard result.exitCode == 0 else {
            if result.stderr.contains(GitCommandRunner.notARepositoryMarker) {
                throw GitServiceError.notARepository
            }
            return nil
        }
        let branch = result.output
        return branch.isEmpty || branch == GitArguments.head ? nil : branch
    }

    func remoteBrowseURL(at path: URL) async throws -> URL? {
        let result = try await runner.run(GitArguments.remotesVerbose, in: path)
        guard result.exitCode == 0 else { return nil }
        return Self.preferredRemote(result.output).flatMap(GitRemoteURL.browseURL(for:))
    }

    func diff(at path: URL) async throws -> String {
        let result = try await runner.run(GitArguments.diffAgainstHead, in: path)
        if result.exitCode == 0 {
            return String(decoding: result.stdout, as: UTF8.self)
        }
        if result.stderr.contains(GitCommandRunner.notARepositoryMarker) {
            throw GitServiceError.notARepository
        }
        let fallback = try await runner.runChecked(GitArguments.diffWorkingTree, in: path)
        return String(decoding: fallback.stdout, as: UTF8.self)
    }

    func recentSubjects(limit: Int, at path: URL) async throws -> [String] {
        let result = try await runner.run(GitArguments.logSubjects + ["\(GitArguments.maxCountFlag)=\(limit)"], in: path)
        guard result.exitCode == 0 else {
            if result.stderr.contains(GitCommandRunner.notARepositoryMarker) {
                throw GitServiceError.notARepository
            }
            // An unborn branch has no log; that is not an error for a style hint.
            return []
        }
        return result.output.split(separator: "\n").map(String.init)
    }

    /// Picks the URL to browse out of `git remote -v`, whose lines read `<name>\t<url> (fetch)`.
    /// Prefers `origin`, then the first remote listed, because a clone without `origin` (renamed,
    /// or several remotes) still has somewhere to browse.
    static func preferredRemote(_ output: String) -> String? {
        var first: String?
        for line in output.split(separator: "\n") {
            let columns = line.split(separator: "\t", maxSplits: 1)
            guard columns.count == 2 else { continue }
            let name = String(columns[0])
            var url = String(columns[1])
            // Push entries repeat the same remote; one of the two directions is enough.
            if let marker = url.range(of: " (") {
                guard url[marker.lowerBound...].hasPrefix(" \(GitArguments.fetchRemoteMarker)") else { continue }
                url = String(url[..<marker.lowerBound])
            }
            if name == GitArguments.defaultRemoteName {
                return url
            }
            first = first ?? url
        }
        return first
    }

    static func parsePorcelain(_ data: Data) -> [GitChange] {
        let entries = data.split(separator: entrySeparator, omittingEmptySubsequences: true)
            .map { String(decoding: $0, as: UTF8.self) }
        var changes: [GitChange] = []
        var index = entries.startIndex
        while index < entries.endIndex {
            let entry = entries[index]
            index += 1
            // "XY path": two status characters, a space, then the path.
            guard entry.count > statusCodeLength + 1 else { continue }
            let status = String(entry.prefix(statusCodeLength))
            let path = String(entry.dropFirst(statusCodeLength + 1))
            changes.append(GitChange(status: status, path: path))
            if status.contains(where: twoPathStatusCodes.contains) {
                // Skip the original path of a rename or copy.
                index += 1
            }
        }
        return changes
    }
}
