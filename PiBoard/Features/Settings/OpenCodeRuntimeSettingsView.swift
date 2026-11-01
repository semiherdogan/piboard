import SwiftUI

struct OpenCodeRuntimeSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    private var runtime: UserInstalledRuntime { environment.openCodeRuntime }

    var body: some View {
        Form {
            Section(AgentKind.opencode.title) {
                AgentEnabledToggle(kind: .opencode)
                AgentExecutablePathField(kind: .opencode, runtime: runtime, autoDetectHint: "~/.opencode/bin/opencode or shell PATH")
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
                    .accessibilityIdentifier(AccessibilityID.openCodeRefresh)
                    RuntimeSetupControls(package: .opencode, runtime: runtime) { [service = environment.openCodeService] in
                        // The service caches a client for the binary found earlier.
                        Task { await service.invalidate() }
                    }
                }
                Text("Install runs the official installer; Update runs opencode upgrade. PiBoard uses the path set above, otherwise the copy it finds at ~/.opencode/bin/opencode or on your shell PATH.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
