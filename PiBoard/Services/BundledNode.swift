import Foundation

enum BundledNodeError: Error, Equatable {
    case missing(URL)
}

/// Resolves the Node runtime bundled into the app. xcodegen's folder-reference resources
/// phase copies `Runtime/node` as `Contents/Resources/node` (the folder's own name, not its
/// repo-relative path), so the bundled layout is `Resources/node/...` rather than
/// `Resources/runtime/node/...`.
struct BundledNode: Equatable {
    private static let relativeNodeExecutablePath = "node/bin/node"
    private static let relativeNPMCLIPath = "node/lib/node_modules/npm/bin/npm-cli.js"

    let nodeExecutable: URL
    let npmCLI: URL

    static func locate(in bundle: Bundle = .main) throws -> BundledNode {
        guard let resourceURL = bundle.resourceURL else {
            throw BundledNodeError.missing(bundle.bundleURL)
        }
        return try locate(root: resourceURL)
    }

    static func locate(root: URL) throws -> BundledNode {
        let nodeExecutable = root.appendingPathComponent(relativeNodeExecutablePath)
        guard FileManager.default.isExecutableFile(atPath: nodeExecutable.path) else {
            throw BundledNodeError.missing(nodeExecutable)
        }
        let npmCLI = root.appendingPathComponent(relativeNPMCLIPath)
        guard FileManager.default.fileExists(atPath: npmCLI.path) else {
            throw BundledNodeError.missing(npmCLI)
        }
        return BundledNode(nodeExecutable: nodeExecutable, npmCLI: npmCLI)
    }
}
