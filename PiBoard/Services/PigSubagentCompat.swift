import Foundation

/// PiG serves `@earendil-works/pi-coding-agent` from `<cell>/runtime/shims`, but subagent extensions spawn
/// `node <package root>/dist/cli.js`, which does not exist there. This adds a forwarder to PiG's own cache,
/// only when the file is missing, and is to be removed once PiG ships it (https://github.com/MichaelKinsy/PiG/issues/395).
enum PigSubagentCompat {
    static let forwarderSource = "import \"../harness/cli.mjs\";\n"
    /// A cell is built while PiG starts, after PiBoard spawned it, so the check repeats.
    static let recheckDelays: [Duration] = [.seconds(5), .seconds(30)]
    private static let cellsDirectoryComponents = ["cells", "node"]
    private static let runtimeDirectoryName = "runtime"
    private static let harnessEntryPath = "harness/cli.mjs"
    private static let forwarderDirectoryName = "dist"
    private static let forwarderFileName = "cli.js"

    // Blocking file I/O: must not run on the main actor.
    @discardableResult
    static func ensureForwarders(cacheRoot: URL, fileManager: FileManager = .default) -> [URL] {
        let cells = cellsDirectoryComponents.reduce(cacheRoot) { $0.appendingPathComponent($1) }
        guard let entries = try? fileManager.contentsOfDirectory(at: cells, includingPropertiesForKeys: nil) else {
            return []
        }
        var written: [URL] = []
        for cell in entries {
            let runtime = cell.appendingPathComponent(runtimeDirectoryName)
            let forwarderDirectory = runtime.appendingPathComponent(forwarderDirectoryName)
            let forwarder = forwarderDirectory.appendingPathComponent(forwarderFileName)
            guard fileManager.fileExists(atPath: runtime.appendingPathComponent(harnessEntryPath).path),
                  !fileManager.fileExists(atPath: forwarder.path) else { continue }
            do {
                try fileManager.createDirectory(at: forwarderDirectory, withIntermediateDirectories: true)
                try Data(forwarderSource.utf8).write(to: forwarder, options: .atomic)
                Diagnostics.process.info("pig subagent forwarder written path=\(forwarder.path, privacy: .public)")
                written.append(forwarder)
            } catch {
                Diagnostics.process.error("pig subagent forwarder failed path=\(forwarder.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return written
    }

    static func schedule(cacheRoot: URL) {
        Task.detached(priority: .utility) {
            ensureForwarders(cacheRoot: cacheRoot)
            for delay in recheckDelays {
                try? await Task.sleep(for: delay)
                ensureForwarders(cacheRoot: cacheRoot)
            }
        }
    }
}
