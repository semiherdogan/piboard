enum LaunchArguments {
    /// In-memory database seeded with SampleData, no Pi runtime, no shells, no Sparkle, no notifications.
    static let uiTesting = "--ui-testing"

    static func contains(_ argument: String, in arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains(argument)
    }
}
