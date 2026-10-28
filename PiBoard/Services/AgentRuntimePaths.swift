import Foundation

/// Layout of the per-user, versioned agent installs under app support.
struct AgentRuntimePaths: Equatable {
    private static let runtimeRelativePath = "runtime"
    private static let currentPointerFileName = "current.json"
    private static let versionsFolderName = "versions"
    private static let npmCacheRelativePath = "runtime/npm-cache"
    private static let nodeModulesFolderName = "node_modules"

    let package: AgentPackage
    let root: URL

    init(package: AgentPackage = .pi, root: URL = (try? AppPaths.applicationSupportDirectory())
        ?? FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/PiBoard")) {
        self.package = package
        self.root = root
    }

    var runtimeRoot: URL {
        root.appendingPathComponent(Self.runtimeRelativePath)
            .appendingPathComponent(package.runtimeFolderName)
    }

    var versionsDirectory: URL {
        runtimeRoot.appendingPathComponent(Self.versionsFolderName)
    }

    func versionDirectory(_ version: String) -> URL {
        versionsDirectory.appendingPathComponent(version)
    }

    var currentPointerFile: URL {
        runtimeRoot.appendingPathComponent(Self.currentPointerFileName)
    }

    var npmCacheDirectory: URL {
        root.appendingPathComponent(Self.npmCacheRelativePath)
    }

    func entry(for version: String) -> URL {
        versionDirectory(version)
            .appendingPathComponent(Self.nodeModulesFolderName)
            .appendingPathComponent(package.npmName)
            .appendingPathComponent(package.entry.relativePath)
    }
}
