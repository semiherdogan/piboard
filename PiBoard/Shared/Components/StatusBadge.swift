import SwiftUI

// Pairs a symbol with text so state is never conveyed by color alone.
struct StatusBadge: View {
    let systemImage: String
    let text: String
    var tint: Color = Color(nsColor: .tertiaryLabelColor)

    var body: some View {
        Label(text, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.caption)
            .foregroundStyle(tint)
    }
}
