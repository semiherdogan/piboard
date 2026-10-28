import SwiftUI

private let installGuideURL = URL(string: "https://opencode.ai/docs")!

struct OpenCodeRuntimeSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    private var runtime: OpenCodeRuntime { environment.openCodeRuntime }

    var body: some View {
        Form {
            Section(AgentKind.opencode.title) {
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
                    if runtime.status == .missing {
                        Link("Install OpenCode", destination: installGuideURL)
                    }
                }
                Text("OpenCode is installed and updated by its own installer. PiBoard uses the copy it finds at ~/.opencode/bin/opencode or on your shell PATH.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
