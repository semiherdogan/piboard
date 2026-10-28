import Foundation
import Testing
@testable import PiBoard

struct WorktreeDoneReminderTests {
    private static let path = URL(fileURLWithPath: "/tmp/worktree")
    private static let branch = "piboard/abcdef12-task"

    private func message(_ sync: BranchSync?) -> String {
        WorktreeDoneReminder.message(branch: Self.branch, path: Self.path, sync: sync)
    }

    @Test func unknownSyncSaysTheBranchCouldNotBeChecked() {
        #expect(message(nil).contains("could not be checked"))
    }

    @Test func anUnpublishedBranchWasNeverPushed() {
        #expect(message(BranchSync(upstream: nil, ahead: 0, behind: 0)).contains("never pushed"))
    }

    @Test func unpushedCommitsAreCounted() {
        #expect(message(BranchSync(upstream: "origin/x", ahead: 1, behind: 0)).contains("1 unpushed commit."))
        #expect(message(BranchSync(upstream: "origin/x", ahead: 2, behind: 0)).contains("2 unpushed commits"))
    }

    @Test func aPushedBranchSaysSo() {
        let text = message(BranchSync(upstream: "origin/x", ahead: 0, behind: 0))
        #expect(text.contains("is pushed"))
        #expect(text.contains(Self.branch))
    }
}
