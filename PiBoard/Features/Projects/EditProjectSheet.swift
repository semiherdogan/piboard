import AppKit
import SwiftUI

struct EditProjectSheet: View {
    let project: Project
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var path: URL

    init(project: Project) {
        self.project = project
        _name = State(initialValue: project.name)
        _path = State(initialValue: project.path)
    }

    private var isNameBlank: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isUnchanged: Bool {
        name == project.name && path == project.path
    }

    private var isPathChanged: Bool {
        ProjectPathService.canonicalize(path) != ProjectPathService.canonicalize(project.path)
    }

    private var isPathLocked: Bool {
        isPathChanged && environment.processes.hasActiveCurrentTreeSession(projectPath: project.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Project")
                .font(.headline)

            InsetTextField(placeholder: "Name", text: $name)

            HStack {
                Text(path.path)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose...") {
                    chooseFolder()
                }
            }

            if isPathLocked {
                Label("Stop the running Pi session before changing the project folder.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    environment.board.updateProject(id: project.id, name: name, path: path)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isNameBlank || isUnchanged || isPathLocked)
            }
        }
        .padding(20)
        .frame(width: 440, height: 240)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = url
    }
}
