import SwiftUI

private let piSpikePrompt = "Say hello and list the files in the current directory."
private let installLogMaxHeight: CGFloat = 120

struct TerminalSpikeView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isFocused = false
    @State private var isDetached = false
    @State private var piLaunchError: String?

    private var session: PTYSession {
        environment.spikeSessionOrCreate()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            piRuntimeHeader
            content
        }
        .padding(isFocused ? 0 : 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Terminal Spike")
    }

    private var header: some View {
        HStack {
            Text("Terminal Spike")
                .font(.headline)
            Label(stateDescription, systemImage: stateSymbol)
                .foregroundStyle(.secondary)
            Spacer()
            Button(isFocused ? "Unfocus Terminal" : "Focus Terminal") {
                isFocused.toggle()
            }
            Button(isDetached ? "Attach" : "Detach") {
                isDetached.toggle()
            }
            Button("Terminate") {
                session.terminate()
            }
            .disabled(!session.state.isRunning)
            if case .exited = session.state {
                Button("Restart Shell") {
                    _ = environment.restartSpikeSession()
                }
            }
        }
        .padding(isFocused ? 24 : 0)
    }

    private var piRuntimeHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Pi runtime")
                    .font(.headline)
                Text(piRuntimeStatusDescription)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Install Latest Pi") {
                    installLatestPi()
                }
                .disabled(isInstalling)
                Button("Launch Pi") {
                    launchPi(prompt: nil)
                }
                .disabled(!isRuntimeReady)
                Button("Launch Pi with prompt") {
                    launchPi(prompt: piSpikePrompt)
                }
                .disabled(!isRuntimeReady)
            }
            if isInstalling || isRuntimeFailed {
                ScrollView {
                    Text(environment.piRuntime.installLog)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxHeight: installLogMaxHeight)
            }
            if let piLaunchError {
                Text(piLaunchError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isDetached {
            ContentUnavailableView("Terminal Detached", systemImage: "terminal")
        } else if isFocused {
            terminalHost
        } else {
            HStack(spacing: 0) {
                Text("Board placeholder")
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .padding(16)
                    .frame(width: 320)
                    .background(.quaternary.opacity(0.4))
                terminalHost
            }
        }
    }

    private var terminalHost: some View {
        ZStack {
            TerminalHostView(session: session)
            if case .exited(let code) = session.state {
                exitedOverlay(exitCode: code)
            }
        }
    }

    private func exitedOverlay(exitCode: Int32?) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(exitCode.map { "Shell exited (\($0))" } ?? "Shell exited")
                .font(.headline)
            Button("Restart Shell") {
                _ = environment.restartSpikeSession()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 320)
    }

    private var stateDescription: String {
        switch session.state {
        case .notStarted: "Not started"
        case .running: "Running"
        case .exited(let code): "Exited(\(code.map(String.init) ?? "?"))"
        }
    }

    private var stateSymbol: String {
        switch session.state {
        case .notStarted: "circle"
        case .running: "circle.fill"
        case .exited: "xmark.circle"
        }
    }

    private var isInstalling: Bool {
        if case .installing = environment.piRuntime.status { return true }
        return false
    }

    private var isRuntimeReady: Bool {
        if case .ready = environment.piRuntime.status { return true }
        return false
    }

    private var isRuntimeFailed: Bool {
        if case .failed = environment.piRuntime.status { return true }
        return false
    }

    private var piRuntimeStatusDescription: String {
        switch environment.piRuntime.status {
        case .unknown: "Unknown"
        case .missing: "Not installed"
        case .installing(let version): "Installing \(version)..."
        case .ready(let version): "Ready (\(version))"
        case .failed(let reason): "Failed: \(reason)"
        }
    }

    private func installLatestPi() {
        Task {
            do {
                let version = try await environment.piRuntime.latestVersionFromRegistry()
                await environment.piRuntime.install(version: version)
            } catch {
                piLaunchError = "Could not fetch latest Pi version: \(error.localizedDescription)"
            }
        }
    }

    private func launchPi(prompt: String?) {
        piLaunchError = nil
        do {
            _ = try environment.launchPiSpike(cwd: FileManager.default.homeDirectoryForCurrentUser, prompt: prompt)
        } catch {
            piLaunchError = "Could not launch Pi: \(error.localizedDescription)"
        }
    }
}
