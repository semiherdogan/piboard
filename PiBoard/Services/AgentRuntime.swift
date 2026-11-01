import Foundation
import Observation

private let bashPath = URL(fileURLWithPath: "/bin/bash")
private let shPath = URL(fileURLWithPath: "/bin/sh")
private let openCodeScriptURL = URL(string: "https://opencode.ai/install")!
private let claudeCodeScriptURL = URL(string: "https://claude.ai/install.sh")!
private let pigScriptURL = URL(string: "https://pi-in-go.dev/install.sh")!
// Skips the shell rc edits; PiBoard finds the binary at its known path instead.
private let openCodeNoModifyPathFlag = "--no-modify-path"
private let openCodeUpdateCommand = "upgrade"
private let selfUpdateCommand = "update"

/// The vendor's own setup script and self-update command for a user-installed agent.
struct UserInstallRecipe: Equatable, Sendable {
    let scriptURL: URL
    /// The script is run by this interpreter rather than piped into a shell.
    let interpreter: URL
    let scriptArguments: [String]
    let updateArguments: [String]
}

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
    let installation: Installation
    /// Nil for managed packages, which PiBoard installs itself.
    let recipe: UserInstallRecipe?

    /// PiG shares `.pi` as its kind, so the engine title is what tells the two apart in the UI.
    var displayName: String {
        self == .pig ? PiEngine.pig.title : kind.title
    }

    enum Installation: Equatable, Sendable {
        /// PiBoard installs versions from npm under `runtime/<folder>/versions`.
        case managed
        /// The tool's own installer owns it; PiBoard only locates the executable.
        case userInstalled(executableName: String, knownPaths: [String])
    }

    static let pi = AgentPackage(
        kind: .pi,
        npmName: "@earendil-works/pi-coding-agent",
        entry: .nodeScript(relativePath: "dist/bundle/cli.js"),
        runtimeFolderName: "pi",
        installation: .managed,
        recipe: nil
    )

    /// Installed by https://opencode.ai/install; it self-updates and runs its own background service, so a
    /// PiBoard-managed copy would run a second version against the same database.
    static let opencode = AgentPackage(
        kind: .opencode,
        npmName: "opencode-ai",
        entry: .binary(relativePath: "bin/opencode"),
        runtimeFolderName: "opencode",
        installation: .userInstalled(executableName: "opencode", knownPaths: ["~/.opencode/bin/opencode"]),
        recipe: UserInstallRecipe(
            scriptURL: openCodeScriptURL,
            interpreter: bashPath,
            scriptArguments: [openCodeNoModifyPathFlag],
            updateArguments: [openCodeUpdateCommand]
        )
    )

    /// Installed by the official Claude Code installer; it self-updates and keeps its sessions under `~/.claude`.
    static let claudeCode = AgentPackage(
        kind: .claudeCode,
        npmName: "@anthropic-ai/claude-code",
        entry: .binary(relativePath: "claude"),
        runtimeFolderName: "claude-code",
        installation: .userInstalled(executableName: "claude", knownPaths: ["~/.local/bin/claude"]),
        recipe: UserInstallRecipe(
            scriptURL: claudeCodeScriptURL,
            interpreter: bashPath,
            scriptArguments: [],
            updateArguments: [selfUpdateCommand]
        )
    )

    /// Installed by https://pi-in-go.dev/install.sh, `go install` or npm; it updates itself with `pig update`.
    static let pig = AgentPackage(
        kind: .pi,
        npmName: "@pi-in-go/pig",
        entry: .binary(relativePath: "pig"),
        runtimeFolderName: "pig",
        installation: .userInstalled(executableName: "pig", knownPaths: ["~/.local/bin/pig", "~/go/bin/pig"]),
        recipe: UserInstallRecipe(
            scriptURL: pigScriptURL,
            interpreter: shPath,
            scriptArguments: [],
            updateArguments: [selfUpdateCommand]
        )
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
