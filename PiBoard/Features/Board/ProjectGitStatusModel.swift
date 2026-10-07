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
    /// Address of the project's Git remote, nil when there is none or it is not browsable.
    private(set) var remoteURL: URL?
    // Exposed so tests can await completion.
    private(set) var refreshTask: Task<Void, Never>?
    private var loadedPath: URL?
    /// Path whose remote is already in `remoteURL`. A remote changes about once in a repository's
    /// life while the status changes constantly, so it is read once and then left alone.
    private var remoteLoadedPath: URL?
    private let git: GitServicing

    init(git: GitServicing) {
        self.git = git
    }

    /// Replaces any in-flight refresh so at most one runs. A refresh of the already loaded path
    /// keeps the previous result visible instead of flashing back to loading.
    ///
    /// `reloadRemote` is for the refresh button: automatic refreshes fire on every task start and
    /// exit, and re-reading an address that did not change would spawn Git for nothing.
    func refresh(path: URL, reloadRemote: Bool = false) {
        refreshTask?.cancel()
        if path != loadedPath {
            state = .loading
        }
        let readsRemote = reloadRemote || path != remoteLoadedPath
        if path != remoteLoadedPath {
            remoteURL = nil
        }
        let git = git
        refreshTask = Task { [weak self] in
            let result: State
            var remote: URL?
            do {
                let info = try await git.repositoryInfo(at: path)
                if info.isRepository {
                    let changes = try await git.status(at: path)
                    result = .ready(branch: info.headBranch, changeCount: changes.count)
                    // A missing remote is not a status failure, so it never fails the refresh.
                    remote = readsRemote ? try? await git.remoteBrowseURL(at: path) : nil
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
            guard readsRemote else { return }
            self.remoteURL = remote
            // Only a successful read is cached, so a failure is retried on the next refresh
            // instead of hiding the button until the user presses reload.
            self.remoteLoadedPath = remote == nil ? nil : path
        }
    }
}
