import SwiftUI

struct PromptEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 120

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(8)
            .editorSurface()
            .frame(minHeight: minHeight)
    }
}
