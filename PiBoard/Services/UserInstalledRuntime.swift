import Foundation
import Observation

/// Finds a user-installed agent binary and reads its version; nothing is installed or removed.
@MainActor
@Observable
final class UserInstalledRuntime: AgentRuntime {
    nonisolated static let versionFlag = "--version"
    nonisolated static let versionTimeout: Duration = .seconds(10)
    private nonisolated static let pathKey = "PATH"

    let package: AgentPackage
    private(set) var status: AgentRuntimeStatus = .unknown
    private(set) var activeVersion: String?
    /// Where the binary was found; nil until a refresh succeeded.
    private(set) var executable: URL?
    private(set) var isRefreshing = false
    @ObservationIgnored var versionsInUse: @MainActor () -> Set<String> = { [] }
    /// Exposed so tests can await a refresh.
    private(set) var refreshTask: Task<Void, Never>?

    @ObservationIgnored private let runner: any CommandRunning
    @ObservationIgnored private let environment: [String: String]
    @ObservationIgnored private let homeDirectory: URL

    init(
        package: AgentPackage,
        runner: any CommandRunning = ProcessCommandRunner(),
        environment: [String: String] = LaunchEnvironment.shared.values,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.package = package
        self.runner = runner
        self.environment = environment
        self.homeDirectory = homeDirectory
    }

    func activeEntry() throws -> (version: String, entry: URL) {
        guard case .ready(let version) = status, let executable else {
            throw PiRuntimeManagerError.noActiveVersion
        }
        return (version, executable)
    }

    func refresh() {
        guard !isRefreshing else { return }
        guard case .userInstalled(let executableName, let knownPaths) = package.installation else {
            apply(nil)
            return
        }
        isRefreshing = true
        let runner = runner
        let environment = environment
        let home = homeDirectory
        refreshTask = Task {
            let detected = await Task.detached(priority: .utility) {
                Self.detect(
                    runner: runner,
                    environment: environment,
                    home: home,
                    executableName: executableName,
                    knownPaths: knownPaths
                )
            }.value
            apply(detected)
            isRefreshing = false
        }
    }

    private func apply(_ detected: (executable: URL, version: String)?) {
        executable = detected?.executable
        activeVersion = detected?.version
        status = detected.map { .ready(version: $0.version) } ?? .missing
    }

    // Blocking: locates the binary and runs `--version`, so it must stay off the main actor.
    private nonisolated static func detect(
        runner: any CommandRunning,
        environment: [String: String],
        home: URL,
        executableName: String,
        knownPaths: [String]
    ) -> (executable: URL, version: String)? {
        guard let executable = ExecutableLocator.locate(
            executableName: executableName,
            knownPaths: knownPaths,
            pathVariable: environment[pathKey],
            home: home
        ) else { return nil }
        guard let result = runner.run(
            executable: executable,
            arguments: [versionFlag],
            environment: environment,
            timeout: versionTimeout
        ), !result.timedOut, result.exitCode == 0,
            let version = ExecutableLocator.parseVersion(result.stdout) else { return nil }
        return (executable, version)
    }
}
