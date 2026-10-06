import SwiftUI

struct TerminalSpikeView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isFocused = false
    @State private var isDetached = false

    private var session: PTYSession {
        environment.spikeSessionOrCreate()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
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
}
