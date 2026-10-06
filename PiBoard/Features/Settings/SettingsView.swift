import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView()
            }
            Tab("Terminal", systemImage: "textformat") {
                TerminalSettingsView()
            }
            Tab("Pi Runtime", systemImage: "terminal") {
                PiRuntimeSettingsView()
            }
        }
        .frame(width: 560, height: 520)
    }
}

private struct GeneralSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var preferences = environment.preferences
        Form {
            Section {
                PromptEditor(text: $preferences.planFirstSuffix, minHeight: 100)
                Text("Appended to the initial prompt when Plan first is checked in task preparation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Plan first")
            }

            Section("External Apps") {
                appPicker("Editor", selection: $preferences.preferredEditor, candidates: ExternalApp.editors)
                appPicker("Terminal", selection: $preferences.preferredTerminal, candidates: ExternalApp.terminals)
            }
        }
        .formStyle(.grouped)
        .onAppear { environment.externalApps.refresh() }
    }

    // The stored choice stays listed even when uninstalled so the picker never shows a blank.
    private func appPicker(_ title: String, selection: Binding<ExternalApp>, candidates: [ExternalApp]) -> some View {
        let actions = environment.externalApps
        let current = selection.wrappedValue
        let apps = candidates.filter { actions.isInstalled($0) || $0 == current }
        return Picker(title, selection: selection) {
            ForEach(apps, id: \.self) { app in
                Text(actions.isInstalled(app) ? app.title : app.title + ExternalAppActions.notInstalledSuffix)
                    .tag(app)
            }
        }
    }
}
