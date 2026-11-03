import SwiftUI

struct PigRuntimeSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    private var runtime: UserInstalledRuntime { environment.pigRuntime }

    var body: some View {
        Form {
            Section(AgentKind.pig.title) {
                AgentEnabledToggle(kind: .pig)
                AgentExecutablePathField(kind: .pig, runtime: runtime, autoDetectHint: "~/.local/bin/pig, ~/go/bin/pig or shell PATH")
                LabeledContent("Status") {
                    RuntimeStatusBadge(status: runtime.status)
                }
                LabeledContent("Version") {
                    Text(runtime.activeVersion ?? "None")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Executable") {
                    Text(runtime.executable.map(ProjectPathService.abbreviated) ?? "Not found")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Refresh") {
                        runtime.refresh()
                    }
                    .disabled(runtime.isRefreshing)
                    .accessibilityIdentifier(AccessibilityID.pigRefresh)
                    RuntimeSetupControls(package: .pig, runtime: runtime)
                }
                Text("Install runs the official installer; Update runs pig update. PiBoard runs PiG with PIG_USE_PI_DIRS=1, so it shares ~/.pi/agent with Pi (sessions, extensions, logins), and adds a forwarder to PiG's extension cache so subagent extensions can start PiG. Commit messages use the model and extensions under Pi Runtime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
