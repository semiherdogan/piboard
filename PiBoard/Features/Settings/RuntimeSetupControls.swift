import SwiftUI

/// Install when the agent is missing, Update when it is ready. Progress and output live in the sheet hosted by SettingsView.
struct RuntimeSetupControls: View {
    @Environment(AppEnvironment.self) private var environment
    let package: AgentPackage
    let runtime: UserInstalledRuntime
    var onFinish: @MainActor () -> Void = {}
    @State private var isConfirmingInstall = false

    private var runner: RuntimeSetupRunner { environment.runtimeSetup }
    private var isDisabled: Bool { !runner.isIdle || runtime.isRefreshing }

    private var isReady: Bool {
        if case .ready = runtime.status { return true }
        return false
    }

    private var installTitle: String { "Install \(package.displayName)" }

    var body: some View {
        HStack {
            if let recipe = package.recipe {
                if runtime.status == .missing {
                    Button(installTitle) {
                        isConfirmingInstall = true
                    }
                    .disabled(isDisabled)
                    .accessibilityIdentifier(AccessibilityID.runtimeInstall(package))
                    .confirmationDialog(installTitle, isPresented: $isConfirmingInstall, titleVisibility: .visible) {
                        Button(installTitle) {
                            start(.install)
                        }
                        .accessibilityIdentifier(AccessibilityID.runtimeInstallConfirm(package))
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("PiBoard downloads \(recipe.scriptURL.absoluteString) and runs it with \(recipe.interpreter.path).")
                    }
                } else if isReady {
                    Button("Update") {
                        start(.update)
                    }
                    .disabled(isDisabled)
                    .accessibilityIdentifier(AccessibilityID.runtimeUpdate(package))
                }
            }
        }
    }

    private func start(_ action: RuntimeSetupAction) {
        runner.start(action, package: package, executable: runtime.executable) { [runtime, onFinish] in
            Task {
                // refresh() is a no-op while one is in flight, so let it land before reading the new state.
                await runtime.refreshTask?.value
                runtime.refresh()
                await runtime.refreshTask?.value
                onFinish()
            }
        }
    }
}
