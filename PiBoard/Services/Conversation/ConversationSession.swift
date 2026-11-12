import Foundation
import Observation

/// One native chat session: a driver process plus the timeline its events build.
@MainActor
@Observable
final class ConversationSession {
    let id = UUID()
    private(set) var state = ConversationState() {
        didSet { refreshLiveStatus() }
    }
    /// Views that must not redraw per streamed delta read this instead of `state`.
    private(set) var liveStatus = ConversationLiveStatus()
    // Reused on purpose: the manager maps both session kinds through the same runtime state.
    private(set) var runtimeState: PTYRuntimeState = .notStarted
    private(set) var info: ConversationSessionInfo?
    private(set) var lastError: String?
    private(set) var thinkingLevels: [String] = []
    private(set) var commands: [ConversationCommand] = []
    private(set) var lastPromptDisposition: PromptDisposition?

    /// Called once the agent has stopped working and stayed quiet, like the pty path.
    var onAgentSettled: (@MainActor () -> Void)?
    var onAgentActivityChanged: (@MainActor (AgentActivity) -> Void)?

    @ObservationIgnored private let driver: any ConversationDriver
    @ObservationIgnored private var activityTracker: AgentActivityTracker?
    @ObservationIgnored private var reportedActivity = AgentActivity.idle
    /// Bumped per send; `inFlightGeneration` is the latest send whose run has not settled, since `state.isRunning` lags the prompt response.
    @ObservationIgnored private var sendGeneration = 0
    @ObservationIgnored private var inFlightGeneration: Int?
    @ObservationIgnored private var hasRequestedCommands = false
    @ObservationIgnored private var dialogTimeouts: [String: Task<Void, Never>] = [:]
    /// Exposed so tests can await the startup work instead of sleeping.
    @ObservationIgnored private(set) var startupTask: Task<Void, Never>?

    var agentActivity: AgentActivity { state.agentActivity }
    var lastStderrLines: [String] { driver.lastStderrLines }
    var processID: pid_t? { driver.processID }
    var executablePath: String? { driver.executablePath }

    init(driver: any ConversationDriver, agentSettleDelay: Duration = AgentActivityTracker.defaultSettleDelay) {
        self.driver = driver
        activityTracker = AgentActivityTracker(settleDelay: agentSettleDelay) { [weak self] in
            self?.onAgentSettled?()
        }
        driver.onEvent = { [weak self] event in
            self?.handle(event)
        }
        driver.onExit = { [weak self] code in
            self?.handleExit(code)
        }
    }

    // MARK: Lifecycle

    func start(initialPrompt: String? = nil) {
        guard launch() else { return }
        startupTask = Task { [weak self] in
            await self?.refreshInfo()
            if let initialPrompt, !initialPrompt.isEmpty {
                await self?.send(initialPrompt)
            }
        }
    }

    func resume() {
        guard launch() else { return }
        startupTask = Task { [weak self] in
            await self?.refreshInfo()
            await self?.loadHistory()
        }
    }

    private func launch() -> Bool {
        do {
            try driver.start()
        } catch {
            lastError = error.localizedDescription
            runtimeState = .exited(nil)
            return false
        }
        runtimeState = .running
        return true
    }

    func stop() {
        driver.shutdown()
    }

    func forceKill() {
        driver.forceKill()
    }

    // MARK: Session data

    func refreshInfo() async {
        await attempt {
            let info = try await driver.state()
            self.info = info
            if let level = info.thinkingLevel { handle(.thinkingLevelChanged(level)) }
            handle(.sessionNameChanged(info.sessionName))
        }
        await attempt { thinkingLevels = try await driver.availableThinkingLevels() }
        await refreshCommands()
    }

    func refreshCommands() async {
        await attempt { commands = try await driver.commands() }
    }

    /// Asks at most once per session, and a failure stays silent: the list is a convenience, not a send error.
    func refreshCommandsIfEmpty() async {
        guard commands.isEmpty, !hasRequestedCommands else { return }
        hasRequestedCommands = true
        if let fetched = try? await driver.commands() { commands = fetched }
    }

    func loadHistory() async {
        await attempt {
            let messages = try await driver.messages()
            state.load(messages: messages)
        }
    }

    func stats() async -> ConversationStats? {
        var result: ConversationStats?
        await attempt { result = try await driver.sessionStats() }
        return result
    }

    func availableModels() async -> [ConversationModel] {
        var result: [ConversationModel] = []
        await attempt { result = try await driver.availableModels() }
        return result
    }

    // MARK: Actions

    /// False when the prompt was not delivered, so the caller can give the text back to the user.
    @discardableResult
    func send(_ text: String, images: [PromptImage] = [], whileRunning: StreamingBehavior = .followUp) async -> Bool {
        var delivered = false
        let behavior = (state.isRunning || inFlightGeneration != nil) ? whileRunning : nil
        sendGeneration += 1
        let generation = sendGeneration
        inFlightGeneration = generation
        await attempt {
            do {
                let disposition = try await driver.prompt(text, images: images, whileRunning: behavior)
                lastPromptDisposition = disposition
                // A handled prompt (extension command) starts no run, so nothing would clear the state.
                if disposition == .handled { clearInFlight(ifLatest: generation) }
                delivered = true
            } catch {
                clearInFlight(ifLatest: generation)
                throw error
            }
        }
        return delivered
    }

    func abort() async {
        await attempt { try await driver.abort() }
    }

    func interrupt() {
        Task { await abort() }
    }

    func clearQueue() async -> (steering: [String], followUp: [String]) {
        var result: (steering: [String], followUp: [String]) = ([], [])
        await attempt { result = try await driver.clearQueue() }
        return result
    }

    /// Unblocks the UI first: a failed write must not leave the dialog on screen.
    func answer(_ answer: ConversationDialogAnswer) {
        guard let dialog = state.pendingDialog else { return }
        resolveDialog(id: dialog.id)
        reportActivity()
        do {
            try driver.answer(dialogID: dialog.id, with: answer)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func dismissError() {
        lastError = nil
    }

    func setThinkingLevel(_ level: String) async {
        await attempt { try await driver.setThinkingLevel(level) }
    }

    func setModel(provider: String, modelID: String) async {
        await attempt {
            try await driver.setModel(provider: provider, modelID: modelID)
            info = try await driver.state()
            thinkingLevels = try await driver.availableThinkingLevels()
        }
    }

    // MARK: Events

    // Assigned only on a real change: an observed write always notifies, even with an equal value.
    private func refreshLiveStatus() {
        let status = ConversationLiveStatus(state)
        if status != liveStatus { liveStatus = status }
    }

    private func handle(_ event: ConversationEvent) {
        ConversationReducer.apply(event, to: &state)
        switch event {
        case .runSettled:
            inFlightGeneration = nil
            cancelDialogTimeouts()
        case .dialogRequested(let dialog): scheduleTimeout(for: dialog)
        default: break
        }
        reportActivity()
    }

    // An older send finishing must not clear the state of a newer send that is still in flight.
    private func clearInFlight(ifLatest generation: Int) {
        if inFlightGeneration == generation { inFlightGeneration = nil }
    }

    private func cancelDialogTimeouts() {
        for timeout in dialogTimeouts.values { timeout.cancel() }
        dialogTimeouts = [:]
    }

    private func resolveDialog(id: String) {
        dialogTimeouts.removeValue(forKey: id)?.cancel()
        state.dialogAnswered(id: id)
    }

    /// Pi resolves a timed-out request on its own side and sends nothing back, so the UI must drop it too.
    private func scheduleTimeout(for dialog: ConversationDialog) {
        guard let timeoutMs = dialog.timeoutMs else { return }
        dialogTimeouts[dialog.id]?.cancel()
        dialogTimeouts[dialog.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(timeoutMs))
            guard !Task.isCancelled, let self else { return }
            resolveDialog(id: dialog.id)
            reportActivity()
        }
    }

    private func handleExit(_ code: Int32?) {
        runtimeState = .exited(code)
        if state.isRunning {
            ConversationReducer.apply(.runSettled(aborted: true), to: &state)
        }
        inFlightGeneration = nil
        cancelDialogTimeouts()
        state.pendingDialogs = []
        // A dead process finishes nothing, so no settled notification may follow.
        activityTracker?.cancel()
        reportActivity(feedingTracker: false)
    }

    private func reportActivity(feedingTracker: Bool = true) {
        let activity = state.agentActivity
        guard activity != reportedActivity else { return }
        reportedActivity = activity
        if feedingTracker { activityTracker?.handle(activity) }
        onAgentActivityChanged?(activity)
    }

    /// Driver failures are shown, never thrown: a chat session must not crash on a bad answer.
    private func attempt(_ work: () async throws -> Void) async {
        do {
            try await work()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
