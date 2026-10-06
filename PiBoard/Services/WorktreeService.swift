import Foundation

protocol WorktreeServicing: Sendable {
    func create(for task: BoardTask, project: Project) async throws -> WorktreeInfo
    func validate(_ info: WorktreeInfo) async -> WorktreeValidation
    func remove(_ info: WorktreeInfo, force: Bool) async throws
    func prune(repository: URL) async throws
}

struct WorktreeInfo: Sendable, Equatable {
    let path: URL
    let branch: String
}

enum WorktreeValidation: Sendable, Equatable {
    case valid
    case pathMissing
    case notAWorktree
    case branchMismatch(actual: String?)
}

final class WorktreeService: WorktreeServicing {
    static let branchPrefix = "piboard/"
    static let taskIDPrefixLength = 8
    static let slugMaxLength = 40
    private static let slugSeparator: Character = "-"
    // Folds non-Latin scripts and diacritics (e.g. Turkish "ç", "ı") to ASCII before slugging.
    private static let asciiTransform = StringTransform("Any-Latin; Latin-ASCII")

    private let runner: GitCommandRunner
    private let git: GitService
    private let rootDirectory: @Sendable () throws -> URL

    init(runner: GitCommandRunner = GitCommandRunner(), rootDirectory: @escaping @Sendable () throws -> URL) {
        self.runner = runner
        self.git = GitService(runner: runner)
        self.rootDirectory = rootDirectory
    }

    func create(for task: BoardTask, project: Project) async throws -> WorktreeInfo {
        let path = Self.managedPath(root: try rootDirectory(), projectID: project.id, taskID: task.id)
        let info = WorktreeInfo(path: path, branch: Self.branchName(taskID: task.id, title: task.title))

        if FileManager.default.fileExists(atPath: path.path), await validate(info) == .valid {
            return info
        }
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)

        let newBranch = GitArguments.worktreeAdd + [GitArguments.newBranchFlag, info.branch, path.path, GitArguments.head]
        let result = try await runner.run(newBranch, in: project.path)
        guard result.exitCode != 0 else { return info }

        // Same task re-run after its worktree was removed: the branch survives, so check it out.
        if result.stderr.contains("'\(info.branch)' already exists") {
            _ = try await runner.runChecked(GitArguments.worktreeAdd + [path.path, info.branch], in: project.path)
            return info
        }
        if result.stderr.contains(GitCommandRunner.notARepositoryMarker) {
            throw GitServiceError.notARepository
        }
        throw GitServiceError.commandFailed(code: result.exitCode, stderr: result.stderr)
    }

    func validate(_ info: WorktreeInfo) async -> WorktreeValidation {
        guard ProjectPathService.exists(info.path) else { return .pathMissing }
        guard let repository = try? await git.repositoryInfo(at: info.path),
              repository.isRepository,
              let topLevel = repository.topLevel,
              ProjectPathService.canonicalize(topLevel) == ProjectPathService.canonicalize(info.path) else {
            return .notAWorktree
        }
        guard repository.headBranch == info.branch else {
            return .branchMismatch(actual: repository.headBranch)
        }
        return .valid
    }

    /// Leaves the branch in place so the task's commits stay reachable.
    func remove(_ info: WorktreeInfo, force: Bool) async throws {
        var arguments = GitArguments.worktreeRemove
        if force {
            arguments.append(GitArguments.forceFlag)
        }
        arguments.append(info.path.path)
        _ = try await runner.runChecked(arguments, in: info.path)
    }

    /// Drops administrative entries for worktrees whose folder was deleted outside Git.
    func prune(repository: URL) async throws {
        _ = try await runner.runChecked(GitArguments.worktreePrune, in: repository)
    }

    static func branchName(taskID: UUID, title: String) -> String {
        let idPart = String(taskID.uuidString.lowercased().prefix(taskIDPrefixLength))
        let slug = slug(title)
        return branchPrefix + (slug.isEmpty ? idPart : idPart + String(slugSeparator) + slug)
    }

    static func slug(_ title: String) -> String {
        let folded = (title.applyingTransform(asciiTransform, reverse: false) ?? title).lowercased()
        var slug = ""
        for character in folded {
            if character.isASCII, character.isLetter || character.isNumber {
                slug.append(character)
            } else if let last = slug.last, last != slugSeparator {
                slug.append(slugSeparator)
            }
        }
        let capped = slug.prefix(slugMaxLength)
        return String(capped).trimmingCharacters(in: CharacterSet(charactersIn: String(slugSeparator)))
    }

    static func managedPath(root: URL, projectID: UUID, taskID: UUID) -> URL {
        root
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent(taskID.uuidString, isDirectory: true)
    }
}
