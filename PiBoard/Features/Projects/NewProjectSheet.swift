import AppKit
import SwiftUI

struct NewProjectSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var path: URL?

    private var isNameBlank: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Project")
                .font(.headline)

            InsetTextField(placeholder: "Name", text: $name)

            HStack {
                Text(path?.path ?? "No folder chosen")
                    .font(.callout)
                    .foregroundStyle(path == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose...") {
                    chooseFolder()
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    guard let path else { return }
                    environment.board.addProject(name: name, path: path)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isNameBlank || path == nil)
            }
        }
        .padding(20)
        .frame(width: 440, height: 220)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = url
        if name.isEmpty {
            name = url.lastPathComponent
        }
    }
}
