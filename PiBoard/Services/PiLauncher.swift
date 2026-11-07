import Foundation

/// How a Pi CLI is started for one run.
enum PiLauncher: Equatable, Sendable {
    /// Pi's npm entry run by the bundled Node.
    case node(executable: URL, entry: URL)
}

/// Builds the launcher for a Pi task from its runtime's active entry.
enum PiEngineLaunch {
    typealias Active = (version: String, entry: URL)
    typealias Resolved = (version: String, launcher: PiLauncher)

    static func pi(active: Active, node: BundledNode) -> Resolved {
        (active.version, .node(executable: node.nodeExecutable, entry: active.entry))
    }
}
