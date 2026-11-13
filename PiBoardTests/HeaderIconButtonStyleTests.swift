import Testing
@testable import PiBoard

struct HeaderIconButtonStyleTests {
    @Test func idleHasNoBackground() {
        #expect(HeaderIconButtonStyle.backgroundOpacity(isPressed: false, isHovered: false, isEnabled: true) == 0)
    }

    @Test func hoverShowsLightBackground() {
        let hovered = HeaderIconButtonStyle.backgroundOpacity(isPressed: false, isHovered: true, isEnabled: true)
        #expect(hovered > 0)
    }

    @Test func pressedIsStrongerThanHover() {
        let hovered = HeaderIconButtonStyle.backgroundOpacity(isPressed: false, isHovered: true, isEnabled: true)
        let pressed = HeaderIconButtonStyle.backgroundOpacity(isPressed: true, isHovered: true, isEnabled: true)
        #expect(pressed > hovered)
    }

    @Test func disabledIgnoresHoverAndDimsContent() {
        #expect(HeaderIconButtonStyle.backgroundOpacity(isPressed: false, isHovered: true, isEnabled: false) == 0)
        #expect(HeaderIconButtonStyle.contentOpacity(isEnabled: false) < HeaderIconButtonStyle.contentOpacity(isEnabled: true))
    }
}
