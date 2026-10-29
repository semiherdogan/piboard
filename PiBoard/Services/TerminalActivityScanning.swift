/// A scanner that reads the agent's activity off the raw pty bytes; one per agent signal shape.
protocol TerminalActivityScanning: Sendable {
    /// Returns the activity changes found in `bytes`, in the order they appear.
    mutating func scan(_ bytes: some RandomAccessCollection<UInt8>) -> [AgentActivity]
}
