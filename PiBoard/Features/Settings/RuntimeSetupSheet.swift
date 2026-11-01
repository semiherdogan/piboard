import SwiftUI

private let sheetMinWidth: CGFloat = 640
private let sheetMinHeight: CGFloat = 400
private let successExitCode: Int32 = 0

struct RuntimeSetupSheet: View {
    let runner: RuntimeSetupRunner

    private var title: String {
        switch runner.state {
        case .idle: ""
        case .downloading(let package): headline(.install, package)
        case .running(let run), .finished(let run, _, _): headline(run.action, run.package)
        case .failed(let package, let action, _): headline(action, package)
        }
    }

    private var statusText: String {
        switch runner.state {
        case .idle: ""
        case .downloading: "Downloading installer..."
        case .running: "Running..."
        case .finished(_, let exitCode, let wasCancelled):
            wasCancelled ? "Stopped." : exitCode.map { $0 == successExitCode ? "Finished." : "Exited with code \($0)." } ?? "Stopped."
        case .failed(_, _, let reason): "Failed: \(reason)"
        }
    }

    private var isRunning: Bool {
        if case .running = runner.state { return true }
        return false
    }

    private var isDownloading: Bool {
        if case .downloading = runner.state { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            switch runner.state {
            case .running(let run), .finished(let run, _, _):
                Text(run.command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                TerminalHostView(taskID: run.id, session: run.session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .downloading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed, .idle:
                Spacer(minLength: 0)
            }
            HStack {
                Text(statusText)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier(AccessibilityID.runtimeSetupStatus)
                Spacer()
                if isRunning {
                    Button("Cancel") {
                        runner.cancel()
                    }
                    .accessibilityIdentifier(AccessibilityID.runtimeSetupCancel)
                } else if isDownloading {
                    Button("Cancel") {
                        runner.cancelDownload()
                    }
                    .accessibilityIdentifier(AccessibilityID.runtimeSetupDownloadCancel)
                } else {
                    Button("Close") {
                        runner.dismiss()
                    }
                    .accessibilityIdentifier(AccessibilityID.runtimeSetupClose)
                }
            }
        }
        .padding()
        .frame(minWidth: sheetMinWidth, minHeight: sheetMinHeight)
        .interactiveDismissDisabled(isRunning || isDownloading)
    }

    private func headline(_ action: RuntimeSetupAction, _ package: AgentPackage) -> String {
        switch action {
        case .install: "Installing \(package.displayName)"
        case .update: "Updating \(package.displayName)"
        }
    }
}
