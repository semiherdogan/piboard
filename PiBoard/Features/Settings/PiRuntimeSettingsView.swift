import AppKit
import SwiftUI

private let installLogMaxHeight: CGFloat = 160

struct PiRuntimeSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var latestVersion: String?
    @State private var isCheckingForUpdates = false
    @State private var isInstalling = false
    @State private var checkError: String?

    private var runtime: PiRuntimeManager { environment.piRuntime }

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Pi Runtime") {
                    statusBadge
                }
                HStack {
                    Button(installButtonTitle) {
                        installLatest()
                    }
                    .disabled(isInstalling)
                    Button("Check for Updates") {
                        checkForUpdates()
                    }
                    .disabled(isCheckingForUpdates)
                    if let latestVersion {
                        Text("Latest: \(latestVersion)")
                            .foregroundStyle(.secondary)
                    }
                }
                if let checkError {
                    Text(checkError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                DisclosureGroup("Install log") {
                    ScrollView {
                        Text(runtime.installLog)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxHeight: installLogMaxHeight)
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
        case .installing(let version):
            Label("Installing \(version)...", systemImage: "arrow.triangle.2.circlepath")
        case .ready(let version):
            Label("Ready (\(version))", systemImage: "checkmark.circle.fill")
        case .failed(let reason):
            Label("Failed: \(reason)", systemImage: "exclamationmark.triangle.fill")
        }
    }

    private var installButtonTitle: String {
        if let latestVersion, case .ready(let current) = runtime.status, current != latestVersion {
            return "Update to \(latestVersion)"
        }
        return "Install Latest Pi"
    }

    private func checkForUpdates() {
        checkError = nil
        isCheckingForUpdates = true
        Task {
            defer { isCheckingForUpdates = false }
            do {
                latestVersion = try await runtime.latestVersionFromRegistry()
            } catch {
                checkError = "Could not fetch latest Pi version: \(error.localizedDescription)"
            }
        }
    }

    private func installLatest() {
        checkError = nil
        isInstalling = true
        Task {
            defer { isInstalling = false }
            do {
                let version: String
                if let latestVersion {
                    version = latestVersion
                } else {
                    version = try await runtime.latestVersionFromRegistry()
                }
                latestVersion = version
                await runtime.install(version: version)
            } catch {
                checkError = "Could not fetch latest Pi version: \(error.localizedDescription)"
            }
        }
    }

    private var userEnvironmentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pi/agent")
    }

    private var userEnvironmentDetected: Bool {
        FileManager.default.fileExists(atPath: userEnvironmentURL.path)
    }
}
