import Foundation
import Observation

/// How an agent's executable is distributed and started.
struct AgentPackage: Equatable, Sendable {
    enum Entry: Equatable, Sendable {
        /// A JavaScript entry run by the bundled Node.
        case nodeScript(relativePath: String)
        /// A native executable inside the installed package tree.
        case binary(relativePath: String)

        var relativePath: String {
            switch self {
            case .nodeScript(let relativePath), .binary(let relativePath): relativePath
            }
        }
    }

    let kind: AgentKind
    /// npm package name; the version is appended at install time.
    let npmName: String
    /// Relative to `<version dir>/node_modules/<npmName>`.
    let entry: Entry
    /// Folder under Application Support, so each kind has its own versions directory.
    let runtimeFolderName: String

    static let pi = AgentPackage(
        kind: .pi,
        npmName: "@earendil-works/pi-coding-agent",
        entry: .nodeScript(relativePath: "dist/bundle/cli.js"),
        runtimeFolderName: "pi"
    )
}

/// Derived from `current.json` only; install workflow progress lives in `AgentRuntimeInstallPhase`
/// so a failed update never hides a working runtime.
enum AgentRuntimeStatus: Equatable, Sendable {
    case unknown
    case missing
    case ready(version: String)
}

enum AgentRuntimeInstallPhase: Equatable, Sendable {
    case idle
    case installing(version: String)
    case activating(version: String)
    case failed(version: String, reason: String)
}

/// What the app needs from an installed agent: is it ready, where is its entry, and which
/// versions must not be deleted. Install, update and rollback stay on the concrete manager
/// because their UI is per tool.
@MainActor
protocol AgentRuntime: AnyObject, Observable {
    var package: AgentPackage { get }
    var status: AgentRuntimeStatus { get }
    var activeVersion: String? { get }
    /// Resolved at launch only, so changing the active version never touches a running session.
    func activeEntry() throws -> (version: String, entry: URL)
    /// Set by the composition root; reports versions that running sessions launched with.
    var versionsInUse: @MainActor () -> Set<String> { get set }
    func refresh()
}
