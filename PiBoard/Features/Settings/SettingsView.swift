import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView()
            }
            Tab("Pi Runtime", systemImage: "terminal") {
                PiRuntimeSettingsView()
            }
        }
        .frame(width: 520, height: 320)
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
        }
        .formStyle(.grouped)
    }
}
