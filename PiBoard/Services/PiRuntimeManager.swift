import Foundation
import Observation

/// Derived from `current.json` only; install workflow progress lives in `PiRuntimeInstallPhase`
/// so a failed update never hides a working runtime.
enum PiRuntimeStatus: Equatable, Sendable {
    case unknown
    case missing
    case ready(version: String)
}

enum PiRuntimeInstallPhase: Equatable, Sendable {
    case idle
    case installing(version: String)
    case activating(version: String)
    case failed(version: String, reason: String)
}

struct CurrentPointer: Codable {
    var activeVersion: String
    var previousVersion: String?
}

enum PiRuntimeRetention {
    static let keptVersions = 3
}

enum PiRuntimeUpdatePolicy {
    static let automaticCheckInterval: TimeInterval = 24 * 60 * 60
}

enum PiRuntimeManagerError: Error, Equatable {
    case noActiveVersion
    case entryMissing(URL)
    case installInProgress
    case verificationFailed(String)
    case invalidRollbackTarget(String)
    case cannotRemoveActiveVersion(String)
    case versionInUse(String)
    case invalidVersion(String)
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
/// outside the main actor) so it can run its blocking calls on a detached task.
enum PiInstallRunner {
    static let npmPackageName = "@earendil-works/pi-coding-agent"
    static let verifyTimeout: Duration = .seconds(20)
    static let logTailLineCount = 40
    private static let npmInstallSubcommand = "install"
    private static let npmCacheEnvKey = "npm_config_cache"
    private static let npmUpdateNotifierEnvKey = "npm_config_update_notifier"
    private static let npmFundEnvKey = "npm_config_fund"
    private static let npmAuditEnvKey = "npm_config_audit"
    private static let disabledFlagValue = "false"
    private static let ciEnvKey = "CI"
    private static let ciEnabledValue = "1"
    private static let termEnvKey = "TERM"
    private static let dumbTerminalValue = "dumb"
    // Inherited values that would redirect the install outside its version directory or
    // inject user Node flags into the bundled runtime.
    private static let strippedEnvKeys = ["NODE_OPTIONS", "NPM_CONFIG_PREFIX", "npm_config_prefix", "PREFIX"]
    private static let versionFlag = "--version"
    private static let helpFlag = "--help"

    static func installEnvironment(
        npmCacheDir: URL,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = sanitizedEnvironment(base)
        environment[npmCacheEnvKey] = npmCacheDir.path
        environment[npmUpdateNotifierEnvKey] = disabledFlagValue
        environment[npmFundEnvKey] = disabledFlagValue
        environment[npmAuditEnvKey] = disabledFlagValue
        return environment
    }

    static func verificationEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = sanitizedEnvironment(base)
        environment[ciEnvKey] = ciEnabledValue
        environment[termEnvKey] = dumbTerminalValue
        return environment
    }

    static func run(
        runner: any PiRuntimeCommandRunning,
        node: BundledNode,
        version: String,
        versionDir: URL,
        npmCacheDir: URL,
        entry: URL
    ) -> InstallOutcome {
        let arguments = [
            node.npmCLI.path,
            npmInstallSubcommand,
            "--prefix", versionDir.path,
            "--no-audit",
            "--no-fund",
            "--loglevel=error",
            "\(npmPackageName)@\(version)"
        ]

        guard let install = runner.run(
            executable: node.nodeExecutable,
            arguments: arguments,
            environment: installEnvironment(npmCacheDir: npmCacheDir),
            timeout: nil
        ) else {
            return InstallOutcome(outcome: .failure("Could not launch npm install"), log: "")
        }

        let log = install.stdout + install.stderr
        guard install.exitCode == 0 else {
            return InstallOutcome(outcome: .failure("npm install exited with status \(install.exitCode)"), log: log)
        }

        if case .failure(let reason, let detail) = verifyVersion(runner: runner, node: node, entry: entry, version: version) {
            return InstallOutcome(outcome: .failure(reason), log: appendingTail(detail, to: log))
        }
        if case .failure(let reason, let detail) = verifyHelp(runner: runner, node: node, entry: entry) {
            return InstallOutcome(outcome: .failure(reason), log: appendingTail(detail, to: log))
        }
        return InstallOutcome(outcome: .success, log: log)
    }

    enum Verification: Sendable, Equatable {
        case success
        case failure(reason: String, stderr: String)
    }

    static func verifyVersion(
        runner: any PiRuntimeCommandRunning,
        node: BundledNode,
        entry: URL,
        version: String
    ) -> Verification {
        guard let result = runVerification(runner: runner, node: node, entry: entry, flag: versionFlag) else {
            return .failure(reason: "Could not launch \(versionFlag) check", stderr: "")
        }
        let reported = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.timedOut, result.exitCode == 0, reported.contains(version) else {
            return .failure(
                reason: "Entry did not report expected version \(version), got: \(reported)",
                stderr: result.stderr
            )
        }
        return .success
    }

    // Catches bundles that print a version but crash once they load the rest of the CLI.
    static func verifyHelp(runner: any PiRuntimeCommandRunning, node: BundledNode, entry: URL) -> Verification {
        guard let result = runVerification(runner: runner, node: node, entry: entry, flag: helpFlag) else {
            return .failure(reason: "Could not launch \(helpFlag) check", stderr: "")
        }
        if result.timedOut {
            return .failure(reason: "\(helpFlag) check timed out", stderr: result.stderr)
        }
        guard result.exitCode == 0 else {
            return .failure(reason: "\(helpFlag) check exited with status \(result.exitCode)", stderr: result.stderr)
        }
        return .success
    }

    static func tail(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(logTailLineCount)
            .joined(separator: "\n")
    }

    private static func runVerification(
        runner: any PiRuntimeCommandRunning,
        node: BundledNode,
        entry: URL,
        flag: String
    ) -> PiRuntimeCommandResult? {
        runner.run(
            executable: node.nodeExecutable,
            arguments: [entry.path, flag],
            environment: verificationEnvironment(),
            timeout: verifyTimeout
        )
    }

    private static func sanitizedEnvironment(_ base: [String: String]) -> [String: String] {
        base.filter { !strippedEnvKeys.contains($0.key) }
    }

    private static func appendingTail(_ stderr: String, to log: String) -> String {
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return log }
        return log + (log.isEmpty || log.hasSuffix("\n") ? "" : "\n") + tail(trimmed)
    }
}

@MainActor
@Observable
final class PiRuntimeManager {
    private static let registryLatestURL = URL(
        string: "https://registry.npmjs.org/\(PiInstallRunner.npmPackageName)/latest"
    )!

    private(set) var status: PiRuntimeStatus = .unknown
    private(set) var installPhase: PiRuntimeInstallPhase = .idle
    private(set) var installLog: String = ""
    // Read from `current.json`, independent of `status` so an in-flight or failed install
    // never loses track of what is on disk.
    private(set) var activeVersion: String?
    private(set) var previousVersion: String?
    private(set) var versions: [String] = []
    private(set) var latestKnownVersion: String?
    private(set) var lastCheckedAt: Date?
    // Set by the composition root; reports versions that running Pi sessions launched with.
    @ObservationIgnored var versionsInUse: @MainActor () -> Set<String> = { [] }

    private let paths: PiRuntimePaths
    private let settings: SettingsRepository?
    private let runner: any PiRuntimeCommandRunning
    private let locateNode: @Sendable () throws -> BundledNode

    init(
        paths: PiRuntimePaths = PiRuntimePaths(),
        settings: SettingsRepository? = nil,
        runner: any PiRuntimeCommandRunning = ProcessCommandRunner(),
        locateNode: @escaping @Sendable () throws -> BundledNode = { try BundledNode.locate() }
    ) {
        self.paths = paths
        self.settings = settings
        self.runner = runner
        self.locateNode = locateNode
        latestKnownVersion = settings?.get(.piLatestKnownVersion)
        lastCheckedAt = settings?.getDouble(.piLastUpdateCheckAt).map(Date.init(timeIntervalSince1970:))
    }

    var isInstalling: Bool {
        switch installPhase {
        case .installing, .activating: true
        case .idle, .failed: false
        }
    }

    /// Versions that must never be deleted: the active one plus any a live session runs.
    func protectedVersions() -> Set<String> {
        var protected = versionsInUse()
        if let activeVersion {
            protected.insert(activeVersion)
        }
        return protected
    }

    var updateAvailable: Bool {
        guard let latest = latestKnownVersion.flatMap(SemanticVersion.init),
              let active = activeVersion.flatMap(SemanticVersion.init) else { return false }
        return latest > active
    }

    func refresh() {
        versions = installedVersions()
        guard let pointer = readCurrentPointer() else {
            activeVersion = nil
            previousVersion = nil
            status = .missing
            return
        }
        activeVersion = pointer.activeVersion
        previousVersion = pointer.previousVersion
        let entry = paths.piEntry(for: pointer.activeVersion)
        status = FileManager.default.fileExists(atPath: entry.path) ? .ready(version: pointer.activeVersion) : .missing
    }

    /// `PiProcessManager` resolves this at launch only, so changing the active version never
    /// touches an already running Pi process.
    func activeEntry() throws -> (version: String, entry: URL) {
        guard case .ready(let version) = status else {
            throw PiRuntimeManagerError.noActiveVersion
        }
        let entry = paths.piEntry(for: version)
        guard FileManager.default.fileExists(atPath: entry.path) else {
            throw PiRuntimeManagerError.entryMissing(entry)
        }
        return (version, entry)
    }

    func installedVersions() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: paths.versionsDirectory.path)) ?? []
        return names
            .compactMap { name in SemanticVersion(name).map { (name: name, version: $0) } }
            .filter { FileManager.default.fileExists(atPath: paths.piEntry(for: $0.name).path) }
            .sorted { $0.version > $1.version }
            .map(\.name)
    }

    func install(version: String) async {
        guard !isInstalling else { return }
        // Reinstalling over an existing install would delete it on failure; activating is enough.
        if installedVersions().contains(version) {
            installLog = ""
            // `activate` records the failure in `installPhase`.
            try? await activate(version: version)
            return
        }

        installPhase = .installing(version: version)
        installLog = ""

        let versionDir = paths.versionDirectory(version)
        let npmCacheDir = paths.npmCacheDirectory
        let entry = paths.piEntry(for: version)

        do {
            try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: npmCacheDir, withIntermediateDirectories: true)
        } catch {
            failInstall(version: version, reason: "Could not create install directories: \(error.localizedDescription)")
            return
        }

        let node: BundledNode
        do {
            node = try locateNode()
        } catch {
            failInstall(version: version, reason: "Bundled node not found: \(error)")
            return
        }

        let runner = runner
        let result = await Task.detached(priority: .userInitiated) {
            PiInstallRunner.run(
                runner: runner,
                node: node,
                version: version,
                versionDir: versionDir,
                npmCacheDir: npmCacheDir,
                entry: entry
            )
        }.value

        installLog = result.log

        switch result.outcome {
        case .success:
            do {
                try writePointer(activating: version)
                installPhase = .idle
                refresh()
                Diagnostics.runtime.info("installed pi \(version, privacy: .public)")
                applyRetention(protected: protectedVersions())
            } catch {
                try? FileManager.default.removeItem(at: versionDir)
                failInstall(version: version, reason: "Install succeeded but could not record current version: \(error.localizedDescription)")
            }
        case .failure(let reason):
            try? FileManager.default.removeItem(at: versionDir)
            failInstall(version: version, reason: reason)
        }
    }

    func activate(version: String) async throws {
        guard !isInstalling else { throw PiRuntimeManagerError.installInProgress }
        installPhase = .activating(version: version)
        do {
            let entry = paths.piEntry(for: version)
            guard FileManager.default.fileExists(atPath: entry.path) else {
                throw PiRuntimeManagerError.entryMissing(entry)
            }
            let node = try locateNode()
            let runner = runner
            let verification = await Task.detached(priority: .userInitiated) {
                PiInstallRunner.verifyVersion(runner: runner, node: node, entry: entry, version: version)
            }.value
            if case .failure(let reason, let stderr) = verification {
                installLog = PiInstallRunner.tail(stderr)
                throw PiRuntimeManagerError.verificationFailed(reason)
            }
            try writePointer(activating: version)
        } catch {
            failInstall(version: version, reason: "Could not activate \(version): \(error)")
            throw error
        }
        installPhase = .idle
        refresh()
        Diagnostics.runtime.info("activated pi \(version, privacy: .public)")
    }

    // Recomputes `status` from disk so a failure never masks the still-valid active version.
    private func failInstall(version: String, reason: String) {
        installPhase = .failed(version: version, reason: reason)
        refresh()
    }

    func rollback(to version: String) async throws {
        guard version != activeVersion, installedVersions().contains(version) else {
            throw PiRuntimeManagerError.invalidRollbackTarget(version)
        }
        try await activate(version: version)
    }

    func removeVersion(_ version: String, protected: Set<String>) throws {
        guard !isInstalling else { throw PiRuntimeManagerError.installInProgress }
        guard version != activeVersion else { throw PiRuntimeManagerError.cannotRemoveActiveVersion(version) }
        guard !protected.contains(version) else { throw PiRuntimeManagerError.versionInUse(version) }
        // Rejects names like `..` that would resolve outside the versions directory.
        guard SemanticVersion(version) != nil else { throw PiRuntimeManagerError.invalidVersion(version) }
        try FileManager.default.removeItem(at: paths.versionDirectory(version))
        refresh()
        Diagnostics.runtime.info("removed pi \(version, privacy: .public)")
    }

    /// Keeps the newest `PiRuntimeRetention.keptVersions` installs plus the active and `protected` ones.
    func applyRetention(protected: Set<String>) {
        let installed = installedVersions()
        var kept = Set(installed.prefix(PiRuntimeRetention.keptVersions)).union(protected)
        if let activeVersion {
            kept.insert(activeVersion)
        }
        for version in installed where !kept.contains(version) {
            do {
                try FileManager.default.removeItem(at: paths.versionDirectory(version))
                Diagnostics.runtime.info("retention removed pi \(version, privacy: .public)")
            } catch {
                Diagnostics.runtime.error("retention could not remove pi \(version, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        versions = installedVersions()
    }

    func checkForUpdates() async throws {
        let latest = try await latestVersionFromRegistry()
        recordLatestVersion(latest, checkedAt: .now)
    }

    func isUpdateCheckDue(now: Date = .now) -> Bool {
        guard let lastCheckedAt else { return true }
        return now.timeIntervalSince(lastCheckedAt) >= PiRuntimeUpdatePolicy.automaticCheckInterval
    }

    /// Background check at app start; failures are silent because the user did not ask for it.
    func checkForUpdatesIfDue(now: Date = .now) {
        guard isUpdateCheckDue(now: now) else { return }
        Task {
            try? await checkForUpdates()
        }
    }

    func recordLatestVersion(_ version: String, checkedAt date: Date) {
        latestKnownVersion = version
        lastCheckedAt = date
        try? settings?.set(.piLatestKnownVersion, value: version)
        try? settings?.setDouble(.piLastUpdateCheckAt, value: date.timeIntervalSince1970)
    }

    /// Throws only when the latest version is unknown and the registry cannot be reached;
    /// install failures surface through `installPhase`.
    func installLatest() async throws {
        if latestKnownVersion == nil {
            try await checkForUpdates()
        }
        guard let latestKnownVersion else { return }
        await install(version: latestKnownVersion)
    }

    // `@concurrent` keeps the request and JSON decoding off the main actor.
    @concurrent
    nonisolated func latestVersionFromRegistry() async throws -> String {
        struct RegistryResponse: Decodable { let version: String }
        let (data, _) = try await URLSession.shared.data(from: Self.registryLatestURL)
        return try JSONDecoder().decode(RegistryResponse.self, from: data).version
    }

    private func readCurrentPointer() -> CurrentPointer? {
        guard let data = try? Data(contentsOf: paths.currentPointerFile) else { return nil }
        return try? JSONDecoder().decode(CurrentPointer.self, from: data)
    }

    private func writePointer(activating version: String) throws {
        let previous = activeVersion == version ? previousVersion : activeVersion
        try Self.writeCurrentPointer(
            CurrentPointer(activeVersion: version, previousVersion: previous),
            to: paths.currentPointerFile
        )
    }

    private static func writeCurrentPointer(_ pointer: CurrentPointer, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(pointer)
        let tempURL = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        try data.write(to: tempURL)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
    }
}
