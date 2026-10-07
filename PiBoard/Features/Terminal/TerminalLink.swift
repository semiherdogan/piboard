import Foundation

/// Resolves what a clicked terminal link should open.
///
/// Everything rendered in the terminal is untrusted: Pi's output, the contents of files the user
/// catted, the response of some HTTP call. Handing such a string straight to LaunchServices would
/// let any of them pick the application that gets launched, so only the schemes below are opened
/// as URLs and everything else has to resolve to a file that exists on disk.
enum TerminalLink {
    enum Target: Equatable {
        case web(URL)
        /// `line` and `column` are nil when the link carried no source location.
        case file(URL, line: Int?, column: Int?)
    }

    /// Schemes whose handler cannot do more than a browser or the mail client would.
    static let allowedSchemes: Set<String> = ["http", "https", "mailto"]
    private static let fileScheme = "file"
    private static let sourceLocationPattern = #":([0-9]+)(?::([0-9]+))?$"#

    /// `workingDirectory` is the directory the terminal's process was started in, which is what a
    /// relative path such as `Sources/App/main.swift` is relative to.
    static func target(
        for link: String,
        workingDirectory: URL,
        fileManager: FileManager = .default
    ) -> Target? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            if scheme == fileScheme, url.isFileURL {
                return fileTarget(for: url.path, workingDirectory: workingDirectory, fileManager: fileManager)
            }
            if allowedSchemes.contains(scheme) {
                return .web(url)
            }
            // Not a scheme we open, but a dot is legal in one, so "main.swift:42" parses as a URL
            // whose scheme is "main.swift". Fall through and let the path branch decide; a link
            // that is neither an allowed scheme nor an existing file ends up refused either way.
        }
        return fileTarget(for: trimmed, workingDirectory: workingDirectory, fileManager: fileManager)
    }

    /// The whole string is checked before the source location is stripped, so a file genuinely
    /// named `notes:12` still wins over reading the same text as line 12 of `notes`.
    private static func fileTarget(
        for path: String,
        workingDirectory: URL,
        fileManager: FileManager
    ) -> Target? {
        if let url = existingFile(at: path, workingDirectory: workingDirectory, fileManager: fileManager) {
            return .file(url, line: nil, column: nil)
        }
        guard let match = path.range(of: sourceLocationPattern, options: .regularExpression) else { return nil }
        let withoutLocation = String(path[..<match.lowerBound])
        guard let url = existingFile(at: withoutLocation, workingDirectory: workingDirectory, fileManager: fileManager) else {
            return nil
        }
        let numbers = path[match.lowerBound...].split(separator: ":").compactMap { Int($0) }
        return .file(url, line: numbers.first, column: numbers.count > 1 ? numbers[1] : nil)
    }

    private static func existingFile(
        at path: String,
        workingDirectory: URL,
        fileManager: FileManager
    ) -> URL? {
        guard !path.isEmpty else { return nil }
        let expanded = NSString(string: path).expandingTildeInPath
        // The base must be flagged as a directory: without it `relativeTo:` treats the last
        // component as a file and resolves the link against the parent instead. `absoluteURL`
        // then drops the base, which a URL built this way would otherwise keep.
        let base = URL(fileURLWithPath: workingDirectory.path, isDirectory: true)
        let url = expanded.hasPrefix("/")
            ? URL(fileURLWithPath: expanded)
            : URL(fileURLWithPath: expanded, relativeTo: base).absoluteURL
        let resolved = url.standardizedFileURL
        return fileManager.fileExists(atPath: resolved.path) ? resolved : nil
    }
}
