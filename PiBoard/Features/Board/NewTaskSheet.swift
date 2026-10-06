import SwiftUI

struct NewTaskSheet: View {
    let projectID: UUID
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var prompt = ""

    private var isTitleBlank: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Task")
                .font(.headline)

            InsetTextField(placeholder: "Title", text: $title)

            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PromptEditor(text: $prompt)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    environment.board.addTask(title: title, prompt: prompt, to: projectID)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTitleBlank)
            }
        }
        .padding(20)
        .frame(width: 440, height: 360)
    }
}
