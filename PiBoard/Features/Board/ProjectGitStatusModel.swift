import Foundation
import Observation

@MainActor
@Observable
final class ProjectGitStatusModel {
    enum State: Equatable {
        case idle
        case loading
        case notRepository
        case ready(branch: String?, changeCount: Int)
        case failed(String)
    }

    private(set) var state: State = .idle
    // Exposed so tests can await completion.
    private(set) var refreshTask: Task<Void, Never>?
    private var loadedPath: URL?
    private let git: GitServicing

    init(git: GitServicing) {
        self.git = git
    }

    /// Replaces any in-flight refresh so at most one runs. A refresh of the already loaded path
    /// keeps the previous result visible instead of flashing back to loading.
    func refresh(path: URL) {
        refreshTask?.cancel()
        if path != loadedPath {
            state = .loading
        }
        let git = git
        refreshTask = Task { [weak self] in
            let result: State
            do {
                let info = try await git.repositoryInfo(at: path)
                if info.isRepository {
                    let changes = try await git.status(at: path)
                    result = .ready(branch: info.headBranch, changeCount: changes.count)
                } else {
                    result = .notRepository
                }
            } catch GitServiceError.notARepository {
                result = .notRepository
            } catch {
                result = .failed(error.localizedDescription)
            }
            guard !Task.isCancelled, let self else { return }
            self.state = result
            self.loadedPath = path
        }
    }
}
