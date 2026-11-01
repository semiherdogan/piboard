import SwiftUI

struct ClaudeCodeRuntimeSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    private var runtime: UserInstalledRuntime { environment.claudeCodeRuntime }
    private var login: ClaudeCodeLoginProbe { environment.claudeCodeLogin }

    private var loginText: String {
        switch login.state {
        case .unknown: "Unknown"
        case .checking: "Checking..."
        case .loggedIn(let method): method.map { "Signed in (\($0))" } ?? "Signed in"
        case .loggedOut: "Not signed in"
        case .failed: "Could not check"
        }
    }

    var body: some View {
        @Bindable var preferences = environment.preferences
        Form {
            Section(AgentKind.claudeCode.title) {
                AgentEnabledToggle(kind: .claudeCode)
                AgentExecutablePathField(kind: .claudeCode, runtime: runtime, autoDetectHint: "~/.local/bin/claude or shell PATH")
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
                LabeledContent("Login") {
                    Text(loginText)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Refresh") {
                        runtime.refresh()
                        if let executable = runtime.executable {
                            login.refresh(executable: executable)
                        }
                    }
                    .disabled(runtime.isRefreshing)
                    .accessibilityIdentifier(AccessibilityID.claudeCodeRefresh)
                    RuntimeSetupControls(package: .claudeCode, runtime: runtime) { [runtime, login] in
                        Task {
                            // The refresh runs detached; the login probe needs its result.
                            await runtime.refreshTask?.value
                            if let executable = runtime.executable {
                                login.refresh(executable: executable)
                            }
                        }
                    }
                }
                Text("Install runs the official installer; Update runs claude update. PiBoard uses the path set above, otherwise the copy it finds at ~/.local/bin/claude or on your shell PATH. Sign in by running claude and /login in a terminal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Commit Messages") {
                TextField("Model", text: $preferences.claudeCommitMessageModel, prompt: Text("model name or alias"))
                Text("Used when Claude Code is the commit message agent (General). Leave empty to let Claude Code choose.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task(id: runtime.executable) {
            if let executable = runtime.executable {
                login.refresh(executable: executable)
            }
        }
    }
}
