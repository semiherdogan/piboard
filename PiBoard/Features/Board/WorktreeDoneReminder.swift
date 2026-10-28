import Foundation

/// Text of the banner shown after a worktree task was moved to Done.
enum WorktreeDoneReminder {
    static let title = "Worktree still on disk"
    static let removeTitle = "Remove Worktree..."
    static let dismissTitle = "Dismiss"

    static func message(branch: String, path: URL, sync: BranchSync?) -> String {
        let location = "The worktree is still at \(ProjectPathService.abbreviated(path))."
        guard let sync else { return "Branch \(branch) could not be checked. \(location)" }
        if !sync.isPublished { return "Branch \(branch) was never pushed. \(location)" }
        if sync.ahead > 0 {
            let unpushed = sync.ahead == 1 ? "1 unpushed commit" : "\(sync.ahead) unpushed commits"
            return "Branch \(branch) has \(unpushed). \(location)"
        }
        return "Branch \(branch) is pushed. \(location)"
    }
}
