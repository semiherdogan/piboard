import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let runner = environment.runtimeSetup
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
            Tab("OpenCode", systemImage: "terminal.fill") {
                OpenCodeRuntimeSettingsView()
            }
            Tab("Claude Code", systemImage: "asterisk") {
                ClaudeCodeRuntimeSettingsView()
            }
        }
        .frame(width: 560, height: 520)
        // Hosted here so a tab switch cannot hide a running setup.
        .sheet(isPresented: Binding(
            get: { runner.presentsSheet },
            set: { isPresented in
                if !isPresented { runner.dismiss() }
            }
        )) {
            RuntimeSetupSheet(runner: runner)
        }
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

            PromptTemplatesSection()

            Section("Projects") {
                Picker("Project view", selection: $preferences.projectLayout) {
                    ForEach(ProjectLayout.allCases, id: \.self) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier(AccessibilityID.projectLayoutSettingPicker)
            }

            Section("External Apps") {
                appPicker("Editor", selection: $preferences.preferredEditor, candidates: ExternalApp.editors)
                appPicker("Terminal", selection: $preferences.preferredTerminal, candidates: ExternalApp.terminals)
            }

            Section("Chat") {
                Picker("Thinking", selection: $preferences.chatThinkingDisplay) {
                    ForEach(ChatThinkingDisplay.allCases, id: \.self) { display in
                        Text(display.title).tag(display)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.chatThinkingDisplayPicker)
                Toggle("Show Tool Details", isOn: $preferences.chatShowsToolDetails)
                    .accessibilityIdentifier(AccessibilityID.chatShowsToolDetails)
                Text("Tool calls always show their name and status; details add the arguments and the result.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            CommitMessagesSection()

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

private struct CommitMessagesSection: View {
    private static let title = "Commit Messages"
    private static let pickerTitle = "Generate with"
    private static let caption = "Drafts the message in the Changes panel. Pi uses the model and extensions under Pi Runtime, Claude Code the model under Claude Code, OpenCode its default model through the background service."

    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var preferences = environment.preferences
        Section(Self.title) {
            Picker(Self.pickerTitle, selection: $preferences.commitMessageAgent) {
                ForEach(preferences.agentChoices, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .accessibilityIdentifier(AccessibilityID.commitMessageAgentPicker)
            Text(Self.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PromptTemplatesSection: View {
    private static let title = "Prompt Templates"
    private static let namePlaceholder = "Name"
    private static let removeSystemImage = "minus.circle"
    private static let removeHelp = "Remove Template"
    private static let addTitle = "Add Template"
    private static let caption = "Insert a template from the menu in New Task and task preparation."
    private static let editorMinHeight: CGFloat = 60

    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var preferences = environment.preferences
        Section(Self.title) {
            ForEach($preferences.promptTemplates) { $template in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField(Self.namePlaceholder, text: $template.name)
                        Button {
                            preferences.promptTemplates.removeAll { $0.id == template.id }
                        } label: {
                            Image(systemName: Self.removeSystemImage)
                        }
                        .buttonStyle(.borderless)
                        .help(Self.removeHelp)
                    }
                    PromptEditor(text: $template.text, minHeight: Self.editorMinHeight)
                }
            }
            Button(Self.addTitle) {
                preferences.promptTemplates.append(PromptTemplate())
            }
            Text(Self.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
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
