import Testing
@testable import PiBoard

struct BranchSyncPresentationTests {
    private static let upstream = "origin/main"

    @Test(arguments: [
        (nil as BranchSync?, "Sync unknown"),
        (BranchSync(upstream: nil, ahead: 0, behind: 0), "Not published"),
        (BranchSync(upstream: upstream, ahead: 2, behind: 3), "2 to push, 3 behind"),
        (BranchSync(upstream: upstream, ahead: 1, behind: 0), "1 to push"),
        (BranchSync(upstream: upstream, ahead: 0, behind: 4), "4 behind"),
        (BranchSync(upstream: upstream, ahead: 0, behind: 0), "Up to date"),
    ])
    func textPerState(sync: BranchSync?, expected: String) {
        #expect(BranchSyncPresentation.text(for: sync) == expected)
    }
}
