import Foundation

/// Text of the sync row in the Changes panel.
enum BranchSyncPresentation {
    static let unknown = "Sync unknown"
    static let unpublished = "Not published"
    static let upToDate = "Up to date"

    static func text(for sync: BranchSync?) -> String {
        guard let sync else { return unknown }
        guard sync.isPublished else { return unpublished }
        switch (sync.ahead > 0, sync.behind > 0) {
        case (true, true): return "\(sync.ahead) to push, \(sync.behind) behind"
        case (true, false): return "\(sync.ahead) to push"
        case (false, true): return "\(sync.behind) behind"
        case (false, false): return upToDate
        }
    }
}
