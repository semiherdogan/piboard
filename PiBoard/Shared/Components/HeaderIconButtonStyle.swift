import SwiftUI

/// Gap between neighbouring header icon buttons; shared so every group of them spaces the same.
let headerIconButtonSpacing: CGFloat = 2
private let targetSize: CGFloat = 22
private let cornerRadius: CGFloat = 5
private let hoverOpacity = 0.12
private let pressedOpacity = 0.22
private let disabledOpacity = 0.35
private let glyphFont = Font.callout
private let menuLabelHorizontalPadding: CGFloat = 3

/// A plain icon with a hover and pressed background, so a small glyph still reads as a button.
struct HeaderIconButtonStyle: ButtonStyle {
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    static func backgroundOpacity(isPressed: Bool, isHovered: Bool, isEnabled: Bool) -> Double {
        if isPressed { return pressedOpacity }
        return isHovered && isEnabled ? hoverOpacity : 0
    }

    static func contentOpacity(isEnabled: Bool) -> Double {
        isEnabled ? 1 : disabledOpacity
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // The glyph size is fixed here so the surrounding text style (caption in a subtitle row) cannot shrink it.
            .font(glyphFont)
            // A custom style loses the plain style's dimming, so a disabled button would look clickable.
            .opacity(Self.contentOpacity(isEnabled: isEnabled))
            .frame(width: targetSize, height: targetSize)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.primary.opacity(Self.backgroundOpacity(isPressed: configuration.isPressed, isHovered: isHovered, isEnabled: isEnabled)))
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { isHovered = $0 }
    }
}

extension ButtonStyle where Self == HeaderIconButtonStyle {
    static var headerIcon: HeaderIconButtonStyle { HeaderIconButtonStyle() }
}

/// Hover background for a `Menu` that keeps `.plain`; a custom button style is not reliably applied to menus on macOS.
private struct HeaderIconHoverModifier: ViewModifier {
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        // No content opacity here: the plain menu style already dims a disabled label.
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.primary.opacity(HeaderIconButtonStyle.backgroundOpacity(isPressed: false, isHovered: isHovered, isEnabled: isEnabled)))
            )
            .onHover { isHovered = $0 }
    }
}

extension View {
    /// Applied to the label inside the `Menu` so the frame and hit area belong to the label itself.
    func headerIconMenuLabel() -> some View {
        self
            .font(glyphFont)
            .padding(.horizontal, menuLabelHorizontalPadding)
            // Min size, not fixed: the Open In label is wider because of its menu indicator.
            .frame(minWidth: targetSize, minHeight: targetSize)
            .contentShape(Rectangle())
    }

    /// Applied outside the `Menu`; the menu sizes it.
    func headerIconHover() -> some View {
        modifier(HeaderIconHoverModifier())
    }
}
