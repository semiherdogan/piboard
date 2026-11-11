import Foundation

struct PiRPCResponse: Equatable, Sendable {
    var id: String?
    var command: String
    var success: Bool
    var data: JSONValue?
    var error: String?
}

/// One decoded stdout line that the driver acts on.
enum PiRPCRecord: Equatable, Sendable {
    case response(PiRPCResponse)
    /// A record can carry more than one event: a streaming update reports usage next to its content delta.
    case events([ConversationEvent])
}
