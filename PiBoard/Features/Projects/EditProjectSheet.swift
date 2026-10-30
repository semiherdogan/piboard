import AppKit
import SwiftUI

struct EditProjectSheet: View {
    let project: Project
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var path: URL
    @State private var defaultAgent: AgentKind

    init(project: Project) {
        self.project = project
        _name = State(initialValue: project.name)
        _path = State(initialValue: project.path)
        _defaultAgent = State(initialValue: project.defaultAgent)
    }

    private var isNameBlank: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isUnchanged: Bool {
        name == project.name && path == project.path && defaultAgent == project.defaultAgent
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

            defaultAgentPicker

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier(AccessibilityID.sheetCancel)
                Button("Save") {
                    environment.board.updateProject(id: project.id, name: name, path: path, defaultAgent: defaultAgent)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isNameBlank || isUnchanged || isPathLocked)
            }
        }
        .padding(20)
        .frame(width: 440, height: 280)
    }

    private var defaultAgentPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            AgentKindPicker(title: "Default agent", selection: $defaultAgent, enabled: environment.preferences.agentChoices)
                .accessibilityIdentifier(AccessibilityID.projectDefaultAgentPicker)
            Text("New tasks start with this agent. Each task can still pick its own.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
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
