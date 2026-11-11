import Foundation
@testable import PiBoard

/// A scripted `ConversationDriver` that records calls and never spawns a process.
@MainActor
final class FakeConversationDriver: ConversationDriver {
    enum Call: Equatable {
        case start
        case prompt(String)
        case abort
        case shutdown
        case forceKill
    }

    var onEvent: (@MainActor (ConversationEvent) -> Void)?
    var onExit: (@MainActor (Int32?) -> Void)?
    var processID: pid_t?
    var executablePath: String?
    var lastStderrLines: [String] = []

    struct PromptRecord: Equatable {
        var text: String
        var whileRunning: StreamingBehavior?
    }

    private(set) var calls: [Call] = []
    private(set) var prompts: [PromptRecord] = []
    private(set) var answeredDialogIDs: [String] = []
    /// True holds every prompt response until it is released, like a prompt whose run is still going.
    var promptGate = false
    var promptDisposition: PromptDisposition = .started
    var promptError: (any Error)?
    private var gatedPrompts: [CheckedContinuation<PromptDisposition, Never>?] = []
    /// Events delivered right after `start()` succeeds.
    var scriptedEvents: [ConversationEvent] = []
    var startError: (any Error)?
    /// False simulates an agent that ignores a closed stdin, so only `forceKill` ends it.
    var exitsOnShutdown = true
    var exitCode: Int32? = 0

    /// Runs inside `start()`, so a test can observe what the manager recorded before the process came up.
    var onStart: (@MainActor () -> Void)?

    func start() throws {
        calls.append(.start)
        onStart?()
        if let startError { throw startError }
        for event in scriptedEvents { onEvent?(event) }
    }

    func prompt(_ text: String, images: [PromptImage], whileRunning: StreamingBehavior?) async throws -> PromptDisposition {
        calls.append(.prompt(text))
        prompts.append(PromptRecord(text: text, whileRunning: whileRunning))
        if let promptError { throw promptError }
        if promptGate {
            return await withCheckedContinuation { gatedPrompts.append($0) }
        }
        return promptDisposition
    }

    func releasePrompts() {
        promptGate = false
        for continuation in gatedPrompts { continuation?.resume(returning: promptDisposition) }
        gatedPrompts = []
    }

    /// Resolves one gated prompt by call order, leaving the others held.
    func releasePrompt(at index: Int, with disposition: PromptDisposition) {
        gatedPrompts[index]?.resume(returning: disposition)
        gatedPrompts[index] = nil
    }

    func abort() async throws {
        calls.append(.abort)
    }

    func clearQueue() async throws -> (steering: [String], followUp: [String]) {
        ([], [])
    }

    func answer(dialogID: String, with answer: ConversationDialogAnswer) throws {
        answeredDialogIDs.append(dialogID)
    }

    func state() async throws -> ConversationSessionInfo {
        ConversationSessionInfo(sessionID: "fake-session")
    }

    func messages() async throws -> [ConversationMessage] { [] }

    func sessionStats() async throws -> ConversationStats { ConversationStats() }

    func availableModels() async throws -> [ConversationModel] { [] }

    func availableThinkingLevels() async throws -> [String] { [] }

    func setThinkingLevel(_ level: String) async throws {}

    func setModel(provider: String, modelID: String) async throws {}

    func commands() async throws -> [ConversationCommand] { [] }

    func shutdown() {
        calls.append(.shutdown)
        if exitsOnShutdown { onExit?(exitCode) }
    }

    func forceKill() {
        calls.append(.forceKill)
        onExit?(nil)
    }

    func emit(_ event: ConversationEvent) {
        onEvent?(event)
    }

    func exit(code: Int32?) {
        onExit?(code)
    }
}
