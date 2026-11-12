import Testing
@testable import PiBoard

struct RuntimeBannerRuleTests {
    @Test func runtimeBannerNeedsPiEnabledAndMissing() {
        #expect(RuntimeBannerRule.showsRuntimeBanner(isPiEnabled: true, status: .missing))
        #expect(!RuntimeBannerRule.showsRuntimeBanner(isPiEnabled: false, status: .missing))
        #expect(!RuntimeBannerRule.showsRuntimeBanner(isPiEnabled: true, status: .ready(version: "1")))
        #expect(!RuntimeBannerRule.showsRuntimeBanner(isPiEnabled: true, status: .unknown))
    }

    @Test func progressHintNeedsPiEnabled() {
        #expect(RuntimeBannerRule.showsTerminalProgressHint(isPiEnabled: true, isNeeded: true, isDismissed: false))
        #expect(!RuntimeBannerRule.showsTerminalProgressHint(isPiEnabled: false, isNeeded: true, isDismissed: false))
        #expect(!RuntimeBannerRule.showsTerminalProgressHint(isPiEnabled: true, isNeeded: true, isDismissed: true))
        #expect(!RuntimeBannerRule.showsTerminalProgressHint(isPiEnabled: true, isNeeded: false, isDismissed: false))
    }
}
