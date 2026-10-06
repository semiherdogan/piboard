import Foundation

/// Single source of truth for canonicalizing and presenting project folder paths.
enum ProjectPathService {
    static func canonicalize(_ url: URL) -> URL {
        // `resolvingSymlinksInPath()` sometimes appends a trailing slash for already-canonical
        // paths; rebuilding the URL from the resolved path string keeps results comparable.
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        return URL(fileURLWithPath: resolved.path)
    }

    static func exists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let found = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return found && isDirectory.boolValue
    }

    static func abbreviated(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
