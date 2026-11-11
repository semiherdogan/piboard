import Foundation

/// What the terminal's progress reporting says the agent is doing right now.
enum AgentActivity: Equatable, Sendable {
    case working
    case idle
    /// The agent is blocked on a permission or a question and will not continue until the user answers in the terminal.
    case needsInput
}
