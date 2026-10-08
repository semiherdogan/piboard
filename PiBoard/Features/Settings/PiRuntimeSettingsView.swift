import AppKit
import SwiftUI

private let installLogMaxHeight: CGFloat = 160

struct PiRuntimeSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isCheckingForUpdates = false
    @State private var actionError: String?

    private var runtime: PiRuntimeManager { environment.piRuntime }

    // `installPhase` covers activation too, so rollback needs no separate busy flag.
    private var isBusy: Bool {
        runtime.isInstalling
    }

    var body: some View {
        @Bindable var preferences = environment.preferences
        Form {
            Section("Pi Runtime") {
                LabeledContent("Status") {
                    statusBadge
                }
                if runtime.installPhase != .idle {
                    LabeledContent("Last install") {
                        installPhaseRow
                    }
                }
                LabeledContent("Installed") {
                    Text(runtime.activeVersion ?? "None")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Latest") {
                    HStack {
                        Text(runtime.latestKnownVersion ?? "unknown")
                        if let lastCheckedAt = runtime.lastCheckedAt {
                            Text("Last checked \(lastCheckedAt, format: .relative(presentation: .named))")
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Check for Updates") {
                        checkForUpdates()
                    }
                    .disabled(isCheckingForUpdates || isBusy)
                    Button(installButtonTitle) {
                        installLatest()
                    }
                    .disabled(isBusy || !canInstall)
                    if let rollbackTarget {
                        Button("Rollback to \(rollbackTarget)") {
                            rollback(to: rollbackTarget)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isBusy)
                    }
                }
                if let actionError {
                    Text(actionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if showsLogTail {
                    Text(PiInstallRunner.tail(runtime.installLog))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }

            Section("Previous Versions") {
                if previousVersions.isEmpty {
                    Text("None")
                        .foregroundStyle(.secondary)
                }
                ForEach(previousVersions, id: \.self) { version in
                    LabeledContent(version) {
                        HStack {
                            Button("Activate") {
                                rollback(to: version)
                            }
                            Button("Remove", role: .destructive) {
                                remove(version)
                            }
                            .disabled(protectedVersions.contains(version))
                            .help(protectedVersions.contains(version) ? "In use by a running session" : "")
                        }
                        .disabled(isBusy)
                    }
                }
            }

            Section("User Environment") {
                LabeledContent("~/.pi/agent") {
                    HStack {
                        Text(userEnvironmentDetected ? "Detected" : "Not found")
                            .foregroundStyle(.secondary)
                        Button("Open Folder") {
                            NSWorkspace.shared.open(userEnvironmentURL)
                        }
                    }
                }
                LabeledContent("Extensions") {
                    HStack {
                        Button("Update Extensions") {
                            updateExtensions()
                        }
                        .disabled(isBusy || runtime.isUpdatingExtensions || !userEnvironmentDetected)
                        extensionUpdateStatus
                    }
                }
                .help("Reconciles the packages declared in your Pi settings. Running sessions keep the extensions they started with.")
                if !runtime.extensionUpdateLog.isEmpty {
                    Text(runtime.extensionUpdateLog)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }

            Section("Commit Messages") {
                TextField("Model", text: $preferences.commitMessageModel, prompt: Text("provider/model"))
                Text("Leave empty to let Pi choose. Example: claude-bridge/claude-sonnet-5-5")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Extensions") {
                    PromptEditor(text: $preferences.headlessExtensionPaths, minHeight: 60)
                }
                Text("One path per line. Loaded on top of --no-extensions for commit message generation. Use this for a provider that comes from an extension, such as pi-claude-bridge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                DisclosureGroup("Install log") {
                    ScrollView {
                        Text(runtime.installLog)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxHeight: installLogMaxHeight)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch runtime.status {
        case .unknown:
            Label("Unknown", systemImage: "questionmark.circle")
        case .missing:
            Label("Not installed", systemImage: "xmark.circle")
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill")
        }
    }

    @ViewBuilder
    private var installPhaseRow: some View {
        switch runtime.installPhase {
        case .idle:
            EmptyView()
        case .installing(let version):
            Label("Installing \(version)...", systemImage: "arrow.triangle.2.circlepath")
        case .activating(let version):
            Label("Activating \(version)...", systemImage: "arrow.triangle.2.circlepath")
        case .failed(let version, let reason):
            HStack {
                Label("Failed: \(reason)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Button("Retry") {
                    retry(version)
                }
                .disabled(isBusy)
            }
        }
    }

    @ViewBuilder
    private var extensionUpdateStatus: some View {
        switch runtime.extensionUpdatePhase {
        case .idle:
            EmptyView()
        case .updating:
            Label("Updating...", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .succeeded(let date):
            Label("Updated \(date, format: .relative(presentation: .named))", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        case .failed(let reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var protectedVersions: Set<String> {
        runtime.protectedVersions()
    }

    private var previousVersions: [String] {
        runtime.versions.filter { $0 != runtime.activeVersion }
    }

    private var rollbackTarget: String? {
        guard let previous = runtime.previousVersion, previousVersions.contains(previous) else { return nil }
        return previous
    }

    private var showsLogTail: Bool {
        switch runtime.installPhase {
        case .installing, .failed: !runtime.installLog.isEmpty
        case .idle, .activating: false
        }
    }

    private var canInstall: Bool {
        if case .ready = runtime.status { return runtime.updateAvailable }
        return true
    }

    private var installButtonTitle: String {
        if runtime.updateAvailable, let latest = runtime.latestKnownVersion {
            return "Update to \(latest)"
        }
        return "Install Latest"
    }

    private func updateExtensions() {
        Task {
            await runtime.updateExtensions()
        }
    }

    private func checkForUpdates() {
        actionError = nil
        isCheckingForUpdates = true
        Task {
            defer { isCheckingForUpdates = false }
            do {
                try await runtime.checkForUpdates()
            } catch {
                actionError = "Could not fetch latest Pi version: \(error.localizedDescription)"
            }
        }
    }

    private func installLatest() {
        actionError = nil
        Task {
            do {
                try await runtime.installLatest()
            } catch {
                actionError = "Could not fetch latest Pi version: \(error.localizedDescription)"
            }
        }
    }

    private func retry(_ version: String) {
        actionError = nil
        Task {
            await runtime.install(version: version)
        }
    }

    private func rollback(to version: String) {
        actionError = nil
        Task {
            do {
                try await runtime.rollback(to: version)
            } catch PiRuntimeManagerError.invalidRollbackTarget(let target) {
                actionError = "Could not activate \(target): not an installed previous version"
            } catch {
                // Activation failures are shown on the "Last install" row.
            }
        }
    }

    private func remove(_ version: String) {
        actionError = nil
        do {
            try runtime.removeVersion(version, protected: protectedVersions)
        } catch {
            actionError = "Could not remove \(version): \(error)"
        }
    }

    private var userEnvironmentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pi/agent")
    }

    private var userEnvironmentDetected: Bool {
        FileManager.default.fileExists(atPath: userEnvironmentURL.path)
    }
}
