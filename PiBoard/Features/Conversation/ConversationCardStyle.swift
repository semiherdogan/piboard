import SwiftUI

enum ConversationLayout {
    static let columnMaxWidth: CGFloat = 820
    static let columnHorizontalPadding: CGFloat = 20

    /// The column's width inside a container of the given width.
    static func columnWidth(in containerWidth: CGFloat) -> CGFloat {
        min(max(containerWidth - 2 * columnHorizontalPadding, 0), columnMaxWidth)
    }
}

private let cardCornerRadius: CGFloat = 12
private let cardPadding: CGFloat = 12
private let cardBorderWidth: CGFloat = 1

private struct ConversationCard: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
        content
            .padding(cardPadding)
            .background(Color(nsColor: .controlBackgroundColor), in: shape)
            .overlay(shape.strokeBorder(.separator, lineWidth: cardBorderWidth))
    }
}

extension View {
    /// The rounded card shared by the composer and the dialog above it.
    func conversationCard() -> some View {
        modifier(ConversationCard())
    }
}
