import Foundation

enum OpenCodeLocator {
    private static let versionPrefix = "v"
    private static let pathSeparator: Character = ":"
    private static let homePrefix = "~/"

    /// Known install locations first (tilde expanded against `home`), then each `PATH` entry.
    static func locate(
        executableName: String,
        knownPaths: [String],
        pathVariable: String?,
        home: URL,
        isExecutable: (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) }
    ) -> URL? {
        let known = knownPaths.map { expand($0, home: home) }
        let onPath = (pathVariable ?? "")
            .split(separator: pathSeparator)
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent(executableName) }
        return (known + onPath).first(where: isExecutable)
    }

    /// "opencode v2.2.0" -> "2.2.0"; tolerant of a missing "v" and trailing text; nil when no digit.
    static func parseVersion(_ output: String) -> String? {
        for token in output.split(whereSeparator: \.isWhitespace) {
            let candidate = token.hasPrefix(versionPrefix) ? token.dropFirst(versionPrefix.count) : token
            if candidate.first?.isNumber == true {
                return String(candidate)
            }
        }
        return nil
    }

    private static func expand(_ path: String, home: URL) -> URL {
        guard path.hasPrefix(homePrefix) else { return URL(fileURLWithPath: path) }
        return home.appendingPathComponent(String(path.dropFirst(homePrefix.count)))
    }
}
