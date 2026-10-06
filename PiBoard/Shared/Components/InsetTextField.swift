import SwiftUI

struct EditorSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(.separatorColor))
            )
    }
}

extension View {
    func editorSurface() -> some View {
        modifier(EditorSurfaceModifier())
    }
}

struct InsetTextField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.body)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .editorSurface()
    }
}
