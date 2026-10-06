import Foundation

/// Layout of the per-user, versioned Pi coding agent installs under app support.
struct PiRuntimePaths: Equatable {
    private static let piPackageName = "@earendil-works/pi-coding-agent"
    private static let piEntryRelativePath = "dist/bundle/cli.js"
    private static let currentPointerRelativePath = "runtime/pi/current.json"
    private static let versionsRelativePath = "runtime/pi/versions"
    private static let npmCacheRelativePath = "runtime/npm-cache"

    let root: URL

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/PiBoard")) {
        self.root = root
    }

    var runtimeRoot: URL {
        root.appendingPathComponent("runtime/pi")
    }

    var versionsDirectory: URL {
        root.appendingPathComponent(Self.versionsRelativePath)
    }

    func versionDirectory(_ version: String) -> URL {
        versionsDirectory.appendingPathComponent(version)
    }

    var currentPointerFile: URL {
        root.appendingPathComponent(Self.currentPointerRelativePath)
    }

    var npmCacheDirectory: URL {
        root.appendingPathComponent(Self.npmCacheRelativePath)
    }

    func piEntry(for version: String) -> URL {
        versionDirectory(version)
            .appendingPathComponent("node_modules")
            .appendingPathComponent(Self.piPackageName)
            .appendingPathComponent(Self.piEntryRelativePath)
    }
}
