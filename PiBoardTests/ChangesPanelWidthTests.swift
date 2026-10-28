import Testing
@testable import PiBoard

struct ChangesPanelWidthTests {
    @Test func preferenceIsUsedWhenItFits() {
        #expect(ChangesPanelWidth.effective(preferred: 440, available: 1000) == 440)
    }

    @Test func panelGivesWayToTheTerminalFloor() {
        let expected = 900 - ChangesPanelWidth.terminalMinimum - ChangesPanelWidth.dividerHitWidth
        #expect(ChangesPanelWidth.effective(preferred: 1200, available: 900) == expected)
    }

    @Test func panelNeverGoesUnderItsMinimum() {
        #expect(ChangesPanelWidth.effective(preferred: 440, available: 400) == ChangesPanelWidth.minimum)
    }

    @Test func preferenceOutsideTheRangeIsClamped() {
        #expect(ChangesPanelWidth.effective(preferred: 50, available: 2000) == ChangesPanelWidth.minimum)
        #expect(ChangesPanelWidth.effective(preferred: 5000, available: 5000) == ChangesPanelWidth.maximum)
    }

    @Test func zeroAvailableBeforeTheFirstLayoutStillReturnsTheMinimum() {
        #expect(ChangesPanelWidth.effective(preferred: 440, available: 0) == ChangesPanelWidth.minimum)
    }
}
