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
        }
        .padding(isFocused ? 24 : 0)
    }

    @ViewBuilder
    private var content: some View {
        if isDetached {
            ContentUnavailableView("Terminal Detached", systemImage: "terminal")
        } else if isFocused {
            TerminalHostView(session: session)
        } else {
            HStack(spacing: 0) {
                Text("Board placeholder")
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .padding(16)
                    .frame(width: 320)
                    .background(.quaternary.opacity(0.4))
                TerminalHostView(session: session)
            }
        }
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
