import Foundation
import Observation

enum PiRuntimeStatus: Equatable, Sendable {
    case unknown
    case missing
    case installing(version: String)
    case ready(version: String)
    case failed(String)
}

struct CurrentPointer: Codable {
    var activeVersion: String
}

enum PiRuntimeManagerError: Error, Equatable {
    case noActiveVersion
    case entryMissing(URL)
}

struct InstallOutcome: Sendable {
    enum Result: Sendable {
        case success
        case failure(String)
    }
    let outcome: Result
    let log: String
}

/// Runs `npm install` and verifies the result. Kept outside `PiRuntimeManager` (and thus
/// outside the main actor) so it can run its blocking `Process` calls on a detached task.
enum PiInstallRunner {
    static let npmPackageName = "@earendil-works/pi-coding-agent"
    private static let npmInstallSubcommand = "install"
    private static let npmCacheEnvKey = "npm_config_cache"
    private static let npmUpdateNotifierEnvKey = "npm_config_update_notifier"
    private static let npmVersionFlag = "--version"

    static func run(
        node: BundledNode,
        version: String,
        versionDir: URL,
        npmCacheDir: URL,
        entry: URL
    ) -> InstallOutcome {
        var environment = ProcessInfo.processInfo.environment
        environment[npmCacheEnvKey] = npmCacheDir.path
        environment[npmUpdateNotifierEnvKey] = "false"

        let arguments = [
            node.npmCLI.path,
            npmInstallSubcommand,
            "--prefix", versionDir.path,
            "--no-audit",
            "--no-fund",
            "--loglevel=error",
            "\(npmPackageName)@\(version)"
        ]

        guard let (exitCode, log) = runProcess(
            executable: node.nodeExecutable,
            arguments: arguments,
            environment: environment
        ) else {
            return InstallOutcome(outcome: .failure("Could not launch npm install"), log: "")
        }

        guard exitCode == 0 else {
            return InstallOutcome(outcome: .failure("npm install exited with status \(exitCode)"), log: log)
        }

        guard let (verifyExitCode, verifyOutput) = runProcess(
            executable: node.nodeExecutable,
            arguments: [entry.path, npmVersionFlag],
            environment: environment
        ) else {
            return InstallOutcome(outcome: .failure("Could not verify install"), log: log)
        }

        let trimmedVerifyOutput = verifyOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard verifyExitCode == 0, trimmedVerifyOutput.contains(version) else {
            return InstallOutcome(
                outcome: .failure(
                    "Installed entry did not report expected version \(version), got: \(trimmedVerifyOutput)"
                ),
                log: log
            )
        }

        return InstallOutcome(outcome: .success, log: log)
    }

    /// Runs synchronously on the calling (already background) thread: drains the pipe before
    /// waiting on exit to avoid deadlocking if npm's output exceeds the pipe buffer.
    private static func runProcess(
        executable: URL,
        arguments: [String],
        environment: [String: String]
    ) -> (exitCode: Int32, output: String)? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }
}

@MainActor
@Observable
final class PiRuntimeManager {
    private static let registryLatestURL = URL(
        string: "https://registry.npmjs.org/\(PiInstallRunner.npmPackageName)/latest"
    )!

    private(set) var status: PiRuntimeStatus = .unknown
    private(set) var installLog: String = ""

    private let paths: PiRuntimePaths

    init(paths: PiRuntimePaths = PiRuntimePaths()) {
        self.paths = paths
    }

    func refresh() {
        guard let data = try? Data(contentsOf: paths.currentPointerFile),
              let pointer = try? JSONDecoder().decode(CurrentPointer.self, from: data) else {
            status = .missing
            return
        }
        let entry = paths.piEntry(for: pointer.activeVersion)
        status = FileManager.default.fileExists(atPath: entry.path) ? .ready(version: pointer.activeVersion) : .missing
    }

    func activeEntry() throws -> URL {
        guard case .ready(let version) = status else {
            throw PiRuntimeManagerError.noActiveVersion
        }
        let entry = paths.piEntry(for: version)
        guard FileManager.default.fileExists(atPath: entry.path) else {
            throw PiRuntimeManagerError.entryMissing(entry)
        }
        return entry
    }

    func install(version: String) async {
        status = .installing(version: version)
        installLog = ""

        let versionDir = paths.versionDirectory(version)
        let npmCacheDir = paths.npmCacheDirectory
        let entry = paths.piEntry(for: version)

        do {
            try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: npmCacheDir, withIntermediateDirectories: true)
        } catch {
            status = .failed("Could not create install directories: \(error.localizedDescription)")
            return
        }

        let node: BundledNode
        do {
            node = try BundledNode.locate()
        } catch {
            status = .failed("Bundled node not found: \(error)")
            return
        }

        let result = await Self.runInstall(
            node: node,
            version: version,
            versionDir: versionDir,
            npmCacheDir: npmCacheDir,
            entry: entry
        )

        installLog = result.log

        switch result.outcome {
        case .success:
            do {
                try Self.writeCurrentPointer(CurrentPointer(activeVersion: version), to: paths.currentPointerFile)
                status = .ready(version: version)
            } catch {
                try? FileManager.default.removeItem(at: versionDir)
                status = .failed("Install succeeded but could not record current version: \(error.localizedDescription)")
            }
        case .failure(let reason):
            try? FileManager.default.removeItem(at: versionDir)
            status = .failed(reason)
        }
    }

    func latestVersionFromRegistry() async throws -> String {
        struct RegistryResponse: Decodable { let version: String }
        let (data, _) = try await URLSession.shared.data(from: Self.registryLatestURL)
        return try JSONDecoder().decode(RegistryResponse.self, from: data).version
    }

    private static func runInstall(
        node: BundledNode,
        version: String,
        versionDir: URL,
        npmCacheDir: URL,
        entry: URL
    ) async -> InstallOutcome {
        await Task.detached(priority: .userInitiated) {
            PiInstallRunner.run(node: node, version: version, versionDir: versionDir, npmCacheDir: npmCacheDir, entry: entry)
        }.value
    }

    private static func writeCurrentPointer(_ pointer: CurrentPointer, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(pointer)
        let tempURL = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        try data.write(to: tempURL)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
    }
}
