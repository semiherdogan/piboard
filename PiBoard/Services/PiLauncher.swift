import Foundation

/// How a Pi-compatible CLI is started for one run.
enum PiLauncher: Equatable, Sendable {
    /// Pi's npm entry run by the bundled Node.
    case node(executable: URL, entry: URL)
    /// PiG's native binary; `environment` is added on top of the launch environment.
    case native(executable: URL, environment: [String: String])
}

enum PigEnvironment {
    static let usePiDirectoriesKey = "PIG_USE_PI_DIRS"
    static let usePiDirectoriesValue = "1"
    static let homeKey = "PIG_HOME"
    private static let pathKey = "PATH"
    private static let pathSeparator = ":"
    private static let defaultHomeRelativePath = ".pig"
    private static let cacheDirectoryName = "cache"

    // Shared Pi dirs keep sessions and logins Pi's; Node goes last on PATH because PiG runs extensions with PATH's `node` and the user's own Node should win for shell commands.
    static func overrides(nodeExecutable: URL, base: [String: String]) -> [String: String] {
        let nodeDirectory = nodeExecutable.deletingLastPathComponent().path
        let path = base[pathKey].flatMap { $0.isEmpty ? nil : $0 + pathSeparator + nodeDirectory } ?? nodeDirectory
        return [usePiDirectoriesKey: usePiDirectoriesValue, pathKey: path]
    }

    static func cacheRoot(environment: [String: String], home: URL) -> URL {
        if let custom = environment[homeKey], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
                .appendingPathComponent(cacheDirectoryName)
        }
        return home
            .appendingPathComponent(defaultHomeRelativePath)
            .appendingPathComponent(cacheDirectoryName)
    }
}

/// Builds the launcher for a .pi or .pig task from its runtime's active entry.
enum PiEngineLaunch {
    typealias Active = (version: String, entry: URL)
    typealias Resolved = (version: String, launcher: PiLauncher)

    static func pi(active: Active, node: BundledNode) -> Resolved {
        (active.version, .node(executable: node.nodeExecutable, entry: active.entry))
    }

    static func pig(active: Active, node: BundledNode, baseEnvironment: [String: String]) -> Resolved {
        let environment = PigEnvironment.overrides(nodeExecutable: node.nodeExecutable, base: baseEnvironment)
        return (active.version, .native(executable: active.entry, environment: environment))
    }
}
