import Foundation

enum AppPaths {
    private static let databaseFileName = "piboard.sqlite"
    private static let worktreesDirectoryName = "worktrees"

    static func applicationSupportDirectory() throws -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PiBoard")
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static func databaseURL() throws -> URL {
        try applicationSupportDirectory().appendingPathComponent(databaseFileName)
    }

    static func worktreesDirectory() throws -> URL {
        let directory = try applicationSupportDirectory().appendingPathComponent(worktreesDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }
}
