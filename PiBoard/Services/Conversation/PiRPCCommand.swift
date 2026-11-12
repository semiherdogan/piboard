import Foundation

/// A line Pi's RPC mode reads on stdin.
enum PiRPCCommand: Equatable, Sendable {
    case prompt(message: String, images: [PromptImage], streaming: StreamingBehavior?)
    case abort
    case clearQueue
    case getState
    case getMessages
    case getEntries
    case getSessionStats
    case getAvailableModels
    case getAvailableThinkingLevels
    case setThinkingLevel(String)
    case setModel(provider: String, modelID: String)
    case getCommands
    /// Answers an `extension_ui_request`; it carries the request's id, not a command id.
    case extensionUIResponse(id: String, answer: ConversationDialogAnswer)

    /// The `type` field on the wire, which a response echoes as `command`.
    var wireName: String {
        switch self {
        case .prompt: "prompt"
        case .abort: "abort"
        case .clearQueue: "clear_queue"
        case .getState: "get_state"
        case .getMessages: "get_messages"
        case .getEntries: "get_entries"
        case .getSessionStats: "get_session_stats"
        case .getAvailableModels: "get_available_models"
        case .getAvailableThinkingLevels: "get_available_thinking_levels"
        case .setThinkingLevel: "set_thinking_level"
        case .setModel: "set_model"
        case .getCommands: "get_commands"
        case .extensionUIResponse: "extension_ui_response"
        }
    }
}
