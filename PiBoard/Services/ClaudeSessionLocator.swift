import Foundation

/// Mirrors Claude Code's session storage (`~/.claude/projects/<encoded cwd>/<session-id>.jsonl`).
/// PiBoard deletes only the session files of tasks it created, when the task is deleted.
enum ClaudeSessionLocator {
    private static let projectsRelativePath = ".claude/projects"
    private static let encodedPathCharacters: Set<Character> = ["/", "."]
    private static let encodedPathReplacement: Character = "-"
    private static let sessionFileExtension = "jsonl"
    private static let hiddenPrefix = "."

    static func defaultProjectsDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(projectsRelativePath, isDirectory: true)
    }

    /// Claude Code sees the real cwd, so symlinks are resolved before encoding.
    static func encodedProjectName(cwd: URL) -> String {
        String(cwd.resolvingSymlinksInPath().path.map { encodedPathCharacters.contains($0) ? encodedPathReplacement : $0 })
    }

    /// A session resumed from another cwd keeps its file in the original folder, so every project folder is scanned.
    static func sessionFile(sessionID: String, cwd: URL, projectsDirectory: URL) -> URL? {
        guard UUID(uuidString: sessionID) != nil else { return nil }
        let fileName = sessionID.lowercased() + "." + sessionFileExtension
        let fileManager = FileManager.default
        let local = projectsDirectory
            .appendingPathComponent(encodedProjectName(cwd: cwd), isDirectory: true)
            .appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: local.path) {
            return local
        }
        guard let names = try? fileManager.contentsOfDirectory(atPath: projectsDirectory.path) else { return nil }
        return names.lazy
            .filter { !$0.hasPrefix(hiddenPrefix) }
            .map { projectsDirectory.appendingPathComponent($0, isDirectory: true).appendingPathComponent(fileName) }
            .first { fileManager.fileExists(atPath: $0.path) }
    }
}
