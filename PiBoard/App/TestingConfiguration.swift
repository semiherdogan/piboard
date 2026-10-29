import Foundation

/// How a hosted test run differs from a normal launch. Both modes run without the network,
/// Sparkle, notifications, the live process registry and global key monitors; UI testing also
/// uses an in-memory database with sample data and a temporary root for everything on disk.
struct TestingConfiguration: Sendable {
    private static let uiTestingDirectoryPrefix = "PiBoardUITesting-"
    private static let worktreesDirectoryName = "worktrees"
    private static let agentDirectoryName = "agent"
    private static let projectsDirectoryName = "projects"
    private static let openCodeConfigDirectoryName = "opencode-config"
    private static let openCodeInstallDirectoryName = "opencode-bin"

    /// Set by XCTest in the hosted app; unit tests must not reach the npm registry.
    let isUnitTesting: Bool
    let isUITesting: Bool
    /// Stands in for Application Support and `~/.pi/agent` while UI tests run; nil otherwise.
    let uiTestingRoot: URL?
    /// Script the UI tests want installed as the Pi entry, so they drive a fake Pi in a real pty.
    let fakePiEntry: URL?
    /// Script the UI tests want found as the `opencode` binary; nil otherwise.
    let fakeOpenCode: URL?

    static let none = TestingConfiguration(isUnitTesting: false, isUITesting: false, uiTestingRoot: nil, fakePiEntry: nil, fakeOpenCode: nil)

    var isRunningTests: Bool { isUnitTesting || isUITesting }

    static func detect(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments
    ) -> TestingConfiguration {
        let isUITesting = LaunchArguments.contains(LaunchArguments.uiTesting, in: arguments)
        return TestingConfiguration(
            isUnitTesting: environment[LaunchEnvironment.testConfigurationEnvKey] != nil,
            isUITesting: isUITesting,
            uiTestingRoot: isUITesting ? makeUITestingDirectory(arguments: arguments) : nil,
            fakePiEntry: isUITesting
                ? LaunchArguments.value(withPrefix: LaunchArguments.uiTestingPiEntryPrefix, in: arguments).map { URL(fileURLWithPath: $0) }
                : nil,
            fakeOpenCode: isUITesting
                ? LaunchArguments.value(withPrefix: LaunchArguments.uiTestingOpenCodePrefix, in: arguments).map { URL(fileURLWithPath: $0) }
                : nil
        )
    }

    /// Where the app copies the fake OpenCode so it can be executed; the fake writes its sidecar files here.
    var fakeOpenCodeInstallDirectory: URL? {
        uiTestingRoot?.appendingPathComponent(Self.openCodeInstallDirectoryName, isDirectory: true)
    }

    /// Stands in for `~/.config/opencode` (service.json) while UI tests run.
    var openCodeConfigDirectory: URL? {
        uiTestingRoot?.appendingPathComponent(Self.openCodeConfigDirectoryName, isDirectory: true)
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

    private static func makeUITestingDirectory(arguments: [String]) -> URL {
        let directory = LaunchArguments.value(withPrefix: LaunchArguments.uiTestingRootPrefix, in: arguments)
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent(uiTestingDirectoryPrefix + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
