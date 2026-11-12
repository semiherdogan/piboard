import SwiftUI

private let newTaskTitle = "New Task"
private let newSessionTitle = "New Session"
private let addTitle = "Add"
private let prepareAndStartTitle = "Prepare and Start"

struct NewTaskSheet: View {
    let projectID: UUID
    // The List layout has no Backlog to park a task in, so the sheet goes straight to preparation.
    var startsImmediately = false
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var prompt = ""

    private var isTitleBlank: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(startsImmediately ? newSessionTitle : newTaskTitle)
                .font(.headline)

            InsetTextField(placeholder: "Title", text: $title)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Prompt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    PromptTemplateMenu(prompt: $prompt)
                }
                PromptEditor(text: $prompt)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier(AccessibilityID.sheetCancel)
                Button(startsImmediately ? prepareAndStartTitle : addTitle) {
                    if startsImmediately {
                        environment.board.addTaskToPrepare(title: title, prompt: prompt, to: projectID)
                    } else {
                        environment.board.addTask(title: title, prompt: prompt, to: projectID)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTitleBlank)
                .accessibilityIdentifier(AccessibilityID.newTaskSubmit)
            }
        }
        .padding(20)
        .frame(width: 440, height: 360)
    }
}
