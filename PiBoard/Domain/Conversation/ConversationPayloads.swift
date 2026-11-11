import Foundation

/// How a prompt sent while a run is open is queued.
enum StreamingBehavior: Equatable, Sendable {
    case steer
    case followUp
}

struct PromptImage: Equatable, Sendable {
    var data: Data
    var mimeType: String
}

/// What the agent did with a submitted prompt.
enum PromptDisposition: String, Equatable, Sendable {
    case started
    case queued
    case handled
}

struct ConversationSessionInfo: Equatable, Sendable {
    var sessionID: String
    var sessionFile: String?
    var sessionName: String?
    var modelID: String?
    var provider: String?
    var thinkingLevel: String?
    var isStreaming = false
    var messageCount = 0
}

struct ConversationStats: Equatable, Sendable {
    var usage = ConversationUsage.zero
    var userMessages = 0
    var assistantMessages = 0
    var toolCalls = 0
    var contextTokens: Int?
    var contextWindow: Int?
    var contextPercent: Double?
}

struct ConversationModel: Equatable, Sendable {
    var id: String
    var provider: String
    var name: String
    var reasoning: Bool
    var acceptsImages: Bool
    var contextWindow: Int?
}

struct ConversationCommand: Equatable, Sendable {
    var name: String
    var description: String?
    var source: String
}
