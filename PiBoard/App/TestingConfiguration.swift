import Foundation

/// How a hosted test run differs from a normal launch. Both modes run without the network,
/// Sparkle, notifications, the live process registry and global key monitors; UI testing also
/// uses an in-memory database with sample data and a temporary root for everything on disk.
struct TestingConfiguration: Sendable {
    private static let uiTestingDirectoryPrefix = "PiBoardUITesting-"
    private static let worktreesDirectoryName = "worktrees"
    private static let agentDirectoryName = "agent"
    private static let projectsDirectoryName = "projects"

    /// Set by XCTest in the hosted app; unit tests must not reach the npm registry.
    let isUnitTesting: Bool
    let isUITesting: Bool
    /// Stands in for Application Support and `~/.pi/agent` while UI tests run; nil otherwise.
    let uiTestingRoot: URL?
    /// Script the UI tests want installed as the Pi entry, so they drive a fake Pi in a real pty.
    let fakePiEntry: URL?

    static let none = TestingConfiguration(isUnitTesting: false, isUITesting: false, uiTestingRoot: nil, fakePiEntry: nil)

    var isRunningTests: Bool { isUnitTesting || isUITesting }

    static func detect(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments
    ) -> TestingConfiguration {
        let isUITesting = LaunchArguments.contains(LaunchArguments.uiTesting, in: arguments)
        return TestingConfiguration(
            isUnitTesting: environment[LaunchEnvironment.testConfigurationEnvKey] != nil,
            isUITesting: isUITesting,
            uiTestingRoot: isUITesting ? makeUITestingDirectory() : nil,
            fakePiEntry: isUITesting
                ? LaunchArguments.value(withPrefix: LaunchArguments.uiTestingPiEntryPrefix, in: arguments).map { URL(fileURLWithPath: $0) }
                : nil
        )
    }

    /// The real ~/.pi/agent must never be read by UI tests; a missing directory skips the resume check.
    var agentDirectory: URL? {
        uiTestingRoot?.appendingPathComponent(Self.agentDirectoryName, isDirectory: true)
    }

    var worktreesRoot: URL? {
        uiTestingRoot?.appendingPathComponent(Self.worktreesDirectoryName, isDirectory: true)
    }

    // Demo paths point into the real home folder; terminals need directories that exist.
    func projectFolder(named name: String) -> URL? {
        uiTestingRoot?
            .appendingPathComponent(Self.projectsDirectoryName, isDirectory: true)
            .appendingPathComponent(slug(name), isDirectory: true)
    }

    private func slug(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    private static func makeUITestingDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(uiTestingDirectoryPrefix + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
