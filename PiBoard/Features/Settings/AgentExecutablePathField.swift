import SwiftUI

/// Optional executable override for a user-installed agent; empty means auto-detect.
struct AgentExecutablePathField: View {
    static let title = "Executable path"
    static let prompt = "Auto-detect"
    static let clearTitle = "Clear"
    static let captionPrefix = "Leave empty to auto-detect at "
    static let captionSuffix = ". A path set here is used as is, with no fallback."

    let kind: AgentKind
    let runtime: UserInstalledRuntime
    let autoDetectHint: String

    @Environment(AppEnvironment.self) private var environment
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    private var stored: String? { environment.preferences.executablePath(for: kind) }

    @ViewBuilder
    var body: some View {
        HStack {
            TextField(Self.title, text: $draft, prompt: Text(Self.prompt))
                .focused($isFocused)
                .onSubmit(commit)
                .accessibilityIdentifier(AccessibilityID.agentExecutablePath(kind))
            if stored != nil {
                Button(Self.clearTitle) {
                    draft = ""
                    commit()
                }
                .accessibilityIdentifier(AccessibilityID.agentExecutablePathClear(kind))
            }
        }
        .onAppear { draft = stored ?? "" }
        .onDisappear(perform: commit)
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
        Text(Self.captionPrefix + autoDetectHint + Self.captionSuffix)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (stored ?? "") else { return }
        environment.preferences.setExecutablePath(trimmed, for: kind)
        draft = trimmed
        runtime.refresh()
        // The service caches a client for the binary found earlier.
        if kind == .opencode {
            Task { [service = environment.openCodeService] in await service.invalidate() }
        }
    }
}
