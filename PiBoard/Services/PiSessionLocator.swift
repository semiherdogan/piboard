import Foundation

/// Mirrors Pi's default session storage (`<agentDir>/sessions/<encoded cwd>/<timestamp>_<id>.jsonl`)
/// so a resume can be checked before spawning. Read-only: PiBoard never writes Pi's files.
enum PiSessionLocator {
    static let agentDirectoryEnvironmentKey = "PI_CODING_AGENT_DIR"
    private static let defaultAgentRelativePath = ".pi/agent"
    private static let sessionsDirectoryName = "sessions"
    private static let pathRoot: Character = "/"
    private static let encodedPathWrapper = "--"
    private static let encodedPathSeparator = "-"
    private static let encodedPathCharacters: Set<Character> = ["/", "\\", ":"]
    private static let sessionFileIDSeparator = "_"
    private static let sessionFileExtension = ".jsonl"

    static func defaultAgentDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment[agentDirectoryEnvironmentKey], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(defaultAgentRelativePath)
    }

    static func sessionsRoot(agentDir: URL) -> URL {
        agentDir.appendingPathComponent(sessionsDirectoryName, isDirectory: true)
    }

    /// Pi encodes the resolved cwd by dropping the leading separator, replacing `/`, `\` and `:`
    /// with `-`, and wrapping the result in `--`. Pi sees the real cwd, so symlinks are resolved.
    static func sessionsDirectory(agentDir: URL = defaultAgentDirectory(), cwd: URL) -> URL {
        var path = ProjectPathService.canonicalize(cwd).path
        if path.first == pathRoot {
            path.removeFirst()
        }
        let encoded = path.map { encodedPathCharacters.contains($0) ? encodedPathSeparator : String($0) }.joined()
        return sessionsRoot(agentDir: agentDir)
            .appendingPathComponent(encodedPathWrapper + encoded + encodedPathWrapper, isDirectory: true)
    }

    /// Checks the cwd's directory first, then every other project directory, because Pi falls
    /// back to a global search when the session is not under the cwd.
    static func sessionFileExists(sessionID: UUID, cwd: URL, agentDir: URL = defaultAgentDirectory()) -> Bool {
        let suffix = (sessionFileIDSeparator + sessionID.uuidString + sessionFileExtension).lowercased()
        let local = sessionsDirectory(agentDir: agentDir, cwd: cwd)
        if containsSessionFile(in: local, suffix: suffix) {
            return true
        }
        let fileManager = FileManager.default
        guard let projectDirectories = try? fileManager.contentsOfDirectory(
            at: sessionsRoot(agentDir: agentDir),
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return false }
        return projectDirectories.contains { directory in
            directory.lastPathComponent != local.lastPathComponent && containsSessionFile(in: directory, suffix: suffix)
        }
    }

    private static func containsSessionFile(in directory: URL, suffix: String) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return false }
        return names.contains { $0.lowercased().hasSuffix(suffix) }
    }
}
