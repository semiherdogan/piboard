import SwiftUI

struct SurfaceCard: ViewModifier {
    var isSelected: Bool = false
    var isHovered: Bool = false

    func body(content: Content) -> some View {
        content
            .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color(.separatorColor), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: .black.opacity(isHovered ? 0.12 : 0), radius: isHovered ? 6 : 0, y: isHovered ? 2 : 0)
    }
}

extension View {
    func surfaceCard(isSelected: Bool = false, isHovered: Bool = false) -> some View {
        modifier(SurfaceCard(isSelected: isSelected, isHovered: isHovered))
    }
}
