enum LaunchArguments {
    /// In-memory database seeded with SampleData, no Pi runtime, no shells, no Sparkle, no notifications.
    static let uiTesting = "--ui-testing"

    /// Path of a script the UI-testing runtime installs as the Pi entry, so tests drive a fake Pi in a real pty.
    static let uiTestingPiEntryPrefix = "--ui-testing-pi-entry="

    /// Path of a script UI tests expose as the `opencode` binary, so tests can pick OpenCode without a real install.
    static let uiTestingOpenCodePrefix = "--ui-testing-opencode="

    /// Path of a script UI tests expose as the `claude` binary, so tests can pick Claude Code without a real install.
    static let uiTestingClaudePrefix = "--ui-testing-claude="

    /// Directory UI tests use as the UI-testing root, so the runner knows where the app's files land.
    static let uiTestingRootPrefix = "--ui-testing-root="

    static func contains(_ argument: String, in arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains(argument)
    }

    static func value(withPrefix prefix: String, in arguments: [String] = CommandLine.arguments) -> String? {
        arguments.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }
}
