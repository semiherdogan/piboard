import Foundation

enum ConversationDriverError: Error, Equatable, LocalizedError {
    case notRunning
    /// The process ended while the command was waiting for its response.
    case exited
    case timeout(String)
    case rejected(command: String, message: String)
    case malformedResponse(String)

    var errorDescription: String? {
        switch self {
        case .notRunning: "The agent is not running."
        case .exited: "The agent exited."
        case .timeout(let command): "The agent did not answer \(command) in time."
        case .rejected(let command, let message): "\(command) failed: \(message)"
        case .malformedResponse(let command): "The agent sent an unreadable answer to \(command)."
        }
    }
}

/// A running agent process that speaks a structured chat protocol. Nothing here names an agent,
/// so `ConversationSession` and the views work for any driver.
@MainActor
protocol ConversationDriver: AnyObject {
    var onEvent: (@MainActor (ConversationEvent) -> Void)? { get set }
    var onExit: (@MainActor (Int32?) -> Void)? { get set }
    var processID: pid_t? { get }
    var executablePath: String? { get }
    /// The most recent diagnostic lines the agent wrote, for an error overlay.
    var lastStderrLines: [String] { get }

    func start() throws
    func prompt(_ text: String, images: [PromptImage], whileRunning: StreamingBehavior?) async throws -> PromptDisposition
    func abort() async throws
    func clearQueue() async throws -> (steering: [String], followUp: [String])
    /// Fire and forget: the agent sends no response to a dialog answer.
    func answer(dialogID: String, with answer: ConversationDialogAnswer) throws
    func state() async throws -> ConversationSessionInfo
    func messages() async throws -> [ConversationMessage]
    func sessionStats() async throws -> ConversationStats
    func availableModels() async throws -> [ConversationModel]
    func availableThinkingLevels() async throws -> [String]
    func setThinkingLevel(_ level: String) async throws
    func setModel(provider: String, modelID: String) async throws
    func commands() async throws -> [ConversationCommand]
    /// Closes stdin, then escalates to SIGTERM and SIGKILL if the process lingers.
    func shutdown()
    func forceKill()
}
