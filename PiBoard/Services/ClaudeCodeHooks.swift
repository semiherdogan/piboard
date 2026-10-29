import Foundation

/// Receives Claude Code's HTTP hooks over loopback. The pty title gives working and idle, so these
/// hooks only carry needs-input and its clearing.
@MainActor
final class ClaudeCodeHooks {
    nonisolated static let hooksKey = "hooks"
    nonisolated static let typeKey = "type"
    nonisolated static let httpType = "http"
    nonisolated static let urlKey = "url"
    nonisolated static let timeoutKey = "timeout"
    nonisolated static let hookTimeoutSeconds = 5
    nonisolated static let pathPrefix = "/hooks/"
    nonisolated static let loopbackHost = "127.0.0.1"
    nonisolated static let permissionRequestEvent = "PermissionRequest"
    nonisolated static let userPromptSubmitEvent = "UserPromptSubmit"
    nonisolated static let stopEvent = "Stop"
    nonisolated static let stopFailureEvent = "StopFailure"
    nonisolated static let sessionEndEvent = "SessionEnd"
    nonisolated static let eventNameKey = "hook_event_name"
    nonisolated static let sessionIDKey = "session_id"
    nonisolated static let subscribedEvents = [permissionRequestEvent, userPromptSubmitEvent, stopEvent, stopFailureEvent, sessionEndEvent]

    var onActivity: @MainActor (UUID, AgentActivity?) -> Void = { _, _ in }
    var onNeedsInput: @MainActor (UUID) -> Void = { _ in }

    /// Token to session id; the token is the only credential in the URL a local process could guess.
    private var tokens: [String: String] = [:]
    private var taskIDs: [String: UUID] = [:]
    private var port: UInt16?
    private var startTask: Task<Void, Never>?
    private let server: any HookServing

    init(server: any HookServing = LoopbackHookServer()) {
        self.server = server
    }

    /// Starts the listener once; concurrent callers await the same start. A failure leaves `port` nil.
    func start() async {
        if port != nil { return }
        if let startTask {
            await startTask.value
            return
        }
        let task = Task { [weak self, server] in
            do {
                // Weak: the server keeps the handler for the app's lifetime.
                let started = try await server.start { [weak self] path, body in
                    Task { @MainActor in self?.apply(path: path, body: body) }
                }
                self?.port = started
            } catch {
                Diagnostics.process.error("Claude Code hook server did not start: \(error.localizedDescription, privacy: .public)")
            }
            self?.startTask = nil
        }
        startTask = task
        await task.value
    }

    /// Builds the `--settings` JSON for one launch, or nil while the listener is not up.
    func settingsJSON(sessionID: String) -> String? {
        guard let port else { return nil }
        tokens = tokens.filter { $0.value != sessionID }
        let token = UUID().uuidString.lowercased()
        tokens[token] = sessionID
        let hook: [String: Any] = [
            Self.typeKey: Self.httpType,
            Self.urlKey: "http://\(Self.loopbackHost):\(port)\(Self.pathPrefix)\(token)",
            Self.timeoutKey: Self.hookTimeoutSeconds,
        ]
        let entry: [String: Any] = [Self.hooksKey: [hook]]
        let hooks = Dictionary(uniqueKeysWithValues: Self.subscribedEvents.map { ($0, [entry]) })
        guard let data = try? JSONSerialization.data(withJSONObject: [Self.hooksKey: hooks], options: [.sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    func register(sessionID: String, taskID: UUID) {
        taskIDs[sessionID] = taskID
    }

    func unregister(taskID: UUID) {
        let sessionIDs = Set(taskIDs.filter { $0.value == taskID }.keys)
        taskIDs = taskIDs.filter { $0.value != taskID }
        tokens = tokens.filter { !sessionIDs.contains($0.value) }
        // The listener stays up for the app's lifetime: a resume can come at any time and it costs nothing.
    }

    /// Test seam and handler target: applies one hook POST.
    func apply(path: String, body: Data) {
        guard path.hasPrefix(Self.pathPrefix),
              let sessionID = tokens[String(path.dropFirst(Self.pathPrefix.count))],
              let taskID = taskIDs[sessionID],
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return }
        if let bodySessionID = json[Self.sessionIDKey] as? String, bodySessionID != sessionID { return }
        switch json[Self.eventNameKey] as? String {
        case Self.permissionRequestEvent:
            onActivity(taskID, .needsInput)
            onNeedsInput(taskID)
        case Self.userPromptSubmitEvent, Self.stopEvent, Self.stopFailureEvent, Self.sessionEndEvent:
            onActivity(taskID, nil)
        default:
            break
        }
    }
}
