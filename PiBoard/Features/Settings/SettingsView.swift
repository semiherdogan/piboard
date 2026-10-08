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
            Tab("Shortcuts", systemImage: "keyboard") {
                ShortcutsSettingsView()
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

            UpdatesSettingsSection()
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

private struct UpdatesSettingsSection: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var updates = environment.updates
        Section("Updates") {
            LabeledContent("Version") {
                Text(UpdateService.versionDescription(infoDictionary: Bundle.main.infoDictionary))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Group {
                HStack {
                    Button("Check for Updates") {
                        updates.checkForUpdates()
                    }
                    .disabled(!updates.canCheckForUpdates)
                    if let lastCheck = updates.lastUpdateCheckDate {
                        Text("Last checked \(lastCheck, format: .relative(presentation: .named))")
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Check automatically", isOn: $updates.automaticallyChecksForUpdates)
                Picker("Channel", selection: $updates.channel) {
                    ForEach(UpdateChannel.allCases) { channel in
                        Text(channel.title).tag(channel)
                    }
                }
                Text("Beta builds may be unstable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!updates.isConfigured)
            if !updates.isConfigured {
                Text(UpdateService.notConfiguredMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
