import Testing
@testable import PiBoard
import Foundation

@MainActor
struct PiRuntimeManagerTests {
    @Test func refreshYieldsMissingWithNoCurrentPointer() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = PiRuntimeManager(paths: PiRuntimePaths(root: root))
        manager.refresh()

        #expect(manager.status == .missing)
    }

    @Test func refreshYieldsReadyWhenEntryExists() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = PiRuntimePaths(root: root)
        let version = "1.0.4"
        let entry = paths.piEntry(for: version)
        try FileManager.default.createDirectory(at: entry.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: entry.path, contents: nil)

        try FileManager.default.createDirectory(
            at: paths.currentPointerFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let pointerData = try JSONEncoder().encode(CurrentPointer(activeVersion: version))
        try pointerData.write(to: paths.currentPointerFile)

        let manager = PiRuntimeManager(paths: paths)
        manager.refresh()

        #expect(manager.status == .ready(version: version))
    }

    @Test func installedVersionsAreSortedNewestFirstAndRequireEntry() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = PiRuntimePaths(root: root)
        for version in ["1.2.0", "1.10.0", "1.10.0-rc.1", "0.9.5"] {
            try installFakeEntry(version, paths: paths)
        }
        try FileManager.default.createDirectory(at: paths.versionDirectory("2.0.0"), withIntermediateDirectories: true)

        let manager = makeManager(paths: paths)

        #expect(manager.installedVersions() == ["1.10.0", "1.10.0-rc.1", "1.2.0", "0.9.5"])
    }

    @Test func activateUpdatesPointerAndRecordsPrevious() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = PiRuntimePaths(root: root)
        try installFakeEntry("1.0.0", paths: paths)
        try installFakeEntry("1.1.0", paths: paths)
        try writePointer(CurrentPointer(activeVersion: "1.0.0"), paths: paths)

        let manager = makeManager(paths: paths)
        manager.refresh()
        try await manager.activate(version: "1.1.0")

        let pointer = try readPointer(paths: paths)
        #expect(pointer.activeVersion == "1.1.0")
        #expect(pointer.previousVersion == "1.0.0")
        #expect(manager.status == .ready(version: "1.1.0"))
        #expect(manager.previousVersion == "1.0.0")
    }

    @Test func activateFailsWhenEntryReportsWrongVersion() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = PiRuntimePaths(root: root)
        try installFakeEntry("1.0.0", paths: paths)
        try installFakeEntry("1.1.0", paths: paths)
        try writePointer(CurrentPointer(activeVersion: "1.0.0"), paths: paths)

        let manager = makeManager(paths: paths, runner: FakeCommandRunner { _ in .ok(stdout: "9.9.9") })
        manager.refresh()

        await #expect(throws: PiRuntimeManagerError.self) {
            try await manager.activate(version: "1.1.0")
        }
        #expect(try readPointer(paths: paths).activeVersion == "1.0.0")
    }

    @Test func rollbackRefusesActiveVersion() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = PiRuntimePaths(root: root)
        try installFakeEntry("1.0.0", paths: paths)
        try writePointer(CurrentPointer(activeVersion: "1.0.0"), paths: paths)

        let manager = makeManager(paths: paths)
        manager.refresh()

        await #expect(throws: PiRuntimeManagerError.invalidRollbackTarget("1.0.0")) {
            try await manager.rollback(to: "1.0.0")
        }
        await #expect(throws: PiRuntimeManagerError.invalidRollbackTarget("0.5.0")) {
            try await manager.rollback(to: "0.5.0")
        }
    }

    @Test func removeVersionRefusesActiveAndDeletesOthers() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = PiRuntimePaths(root: root)
        try installFakeEntry("1.0.0", paths: paths)
        try installFakeEntry("1.1.0", paths: paths)
        try writePointer(CurrentPointer(activeVersion: "1.1.0"), paths: paths)

        let manager = makeManager(paths: paths)
        manager.refresh()

        #expect(throws: PiRuntimeManagerError.cannotRemoveActiveVersion("1.1.0")) {
            try manager.removeVersion("1.1.0", protected: [])
        }
        try manager.removeVersion("1.0.0", protected: [])

        #expect(FileManager.default.fileExists(atPath: paths.versionDirectory("1.1.0").path))
        #expect(!FileManager.default.fileExists(atPath: paths.versionDirectory("1.0.0").path))
        #expect(manager.versions == ["1.1.0"])
    }

    @Test func retentionKeepsNewestThreePlusActive() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = PiRuntimePaths(root: root)
        for version in ["1.0.0", "1.1.0", "1.2.0", "1.3.0", "1.4.0"] {
            try installFakeEntry(version, paths: paths)
        }
        try writePointer(CurrentPointer(activeVersion: "1.0.0"), paths: paths)

        let manager = makeManager(paths: paths)
        manager.refresh()
        manager.applyRetention(protected: [])

        #expect(manager.installedVersions() == ["1.4.0", "1.3.0", "1.2.0", "1.0.0"])
    }

    @Test func retentionSkipsProtectedVersion() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = PiRuntimePaths(root: root)
        for version in ["1.0.0", "1.1.0", "1.2.0", "1.3.0", "1.4.0"] {
            try installFakeEntry(version, paths: paths)
        }
        try writePointer(CurrentPointer(activeVersion: "1.4.0"), paths: paths)

        let manager = makeManager(paths: paths)
        manager.refresh()
        manager.applyRetention(protected: ["1.0.0"])

        #expect(manager.installedVersions() == ["1.4.0", "1.3.0", "1.2.0", "1.0.0"])
    }

    @Test func removeVersionRefusesProtectedVersion() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = PiRuntimePaths(root: root)
        try installFakeEntry("1.0.0", paths: paths)
        try installFakeEntry("1.1.0", paths: paths)
        try writePointer(CurrentPointer(activeVersion: "1.1.0"), paths: paths)

        let manager = makeManager(paths: paths)
        manager.versionsInUse = { ["1.0.0"] }
        manager.refresh()

        #expect(throws: PiRuntimeManagerError.versionInUse("1.0.0")) {
            try manager.removeVersion("1.0.0", protected: manager.protectedVersions())
        }
        #expect(FileManager.default.fileExists(atPath: paths.versionDirectory("1.0.0").path))
    }

    @Test func installVerifiesActivatesAndAppliesRetention() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = PiRuntimePaths(root: root)
        for version in ["1.0.0", "1.1.0", "1.2.0"] {
            try installFakeEntry(version, paths: paths)
        }
        try writePointer(CurrentPointer(activeVersion: "1.2.0"), paths: paths)
        let newVersion = "2.0.0"
        let newEntry = paths.piEntry(for: newVersion)
        let calls = CallRecorder()
        let runner = FakeCommandRunner { arguments in
            calls.record(arguments)
            if arguments.contains("install") {
                try? FileManager.default.createDirectory(at: newEntry.deletingLastPathComponent(), withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: newEntry.path, contents: nil)
            }
            return .ok(stdout: newVersion)
        }

        let manager = makeManager(paths: paths, runner: runner)
        manager.refresh()
        await manager.install(version: newVersion)

        #expect(manager.status == .ready(version: newVersion))
        #expect(manager.previousVersion == "1.2.0")
        #expect(manager.installedVersions() == ["2.0.0", "1.2.0", "1.1.0"])
        #expect(calls.arguments.contains { $0 == [newEntry.path, "--help"] })
    }

    @Test func installFailsWhenHelpCheckFails() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = PiRuntimePaths(root: root)
        let version = "2.0.0"
        let entry = paths.piEntry(for: version)
        let runner = FakeCommandRunner { arguments in
            if arguments.contains("install") {
                try? FileManager.default.createDirectory(at: entry.deletingLastPathComponent(), withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: entry.path, contents: nil)
            }
            if arguments.contains("--help") {
                return CommandResult(exitCode: 1, stdout: "", stderr: "Error: cannot find module", timedOut: false)
            }
            return .ok(stdout: version)
        }

        let manager = makeManager(paths: paths, runner: runner)
        manager.refresh()
        await manager.install(version: version)

        #expect(manager.status == .missing)
        guard case .failed(let failedVersion, _) = manager.installPhase else {
            Issue.record("expected failed install phase, got \(manager.installPhase)")
            return
        }
        #expect(failedVersion == version)
        #expect(manager.installLog.contains("cannot find module"))
        #expect(!FileManager.default.fileExists(atPath: paths.versionDirectory(version).path))
    }

    @Test func failedUpdateKeepsActiveVersionReady() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = PiRuntimePaths(root: root)
        try installFakeEntry("1.0.0", paths: paths)
        try writePointer(CurrentPointer(activeVersion: "1.0.0"), paths: paths)
        let runner = FakeCommandRunner { arguments in
            arguments.contains("install")
                ? CommandResult(exitCode: 1, stdout: "", stderr: "E404", timedOut: false)
                : .ok(stdout: "")
        }

        let manager = makeManager(paths: paths, runner: runner)
        manager.refresh()
        await manager.install(version: "2.0.0")

        #expect(manager.status == .ready(version: "1.0.0"))
        guard case .failed(let failedVersion, _) = manager.installPhase else {
            Issue.record("expected failed install phase, got \(manager.installPhase)")
            return
        }
        #expect(failedVersion == "2.0.0")
        #expect(try readPointer(paths: paths).activeVersion == "1.0.0")
    }

    @Test func updateAvailableComparesLatestWithActive() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = PiRuntimePaths(root: root)
        try installFakeEntry("1.2.0", paths: paths)
        try writePointer(CurrentPointer(activeVersion: "1.2.0"), paths: paths)

        let manager = makeManager(paths: paths)
        manager.refresh()
        #expect(!manager.updateAvailable)

        manager.recordLatestVersion("1.10.0", checkedAt: .now)
        #expect(manager.updateAvailable)

        manager.recordLatestVersion("1.2.0", checkedAt: .now)
        #expect(!manager.updateAvailable)

        manager.recordLatestVersion("1.2.0-rc.1", checkedAt: .now)
        #expect(!manager.updateAvailable)
    }

    @Test func latestVersionPersistsAndDrivesCheckInterval() throws {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)
        let settings = SettingsRepository(database: database)
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let checkedAt = Date(timeIntervalSince1970: 1_000_000)

        let first = makeManager(paths: PiRuntimePaths(root: root), settings: settings)
        #expect(first.isUpdateCheckDue(now: checkedAt))
        first.recordLatestVersion("3.0.0", checkedAt: checkedAt)

        let second = makeManager(paths: PiRuntimePaths(root: root), settings: settings)
        #expect(second.latestKnownVersion == "3.0.0")
        #expect(second.lastCheckedAt == checkedAt)
        #expect(!second.isUpdateCheckDue(now: checkedAt.addingTimeInterval(PiRuntimeUpdatePolicy.automaticCheckInterval - 1)))
        #expect(second.isUpdateCheckDue(now: checkedAt.addingTimeInterval(PiRuntimeUpdatePolicy.automaticCheckInterval)))
    }

    @Test func installEnvironmentStripsUserNodeAndPrefixSettings() {
        let base = ["PATH": "/usr/bin", "NODE_OPTIONS": "--inspect", "NPM_CONFIG_PREFIX": "/x", "npm_config_prefix": "/y", "PREFIX": "/z"]
        let environment = PiInstallRunner.installEnvironment(npmCacheDir: URL(fileURLWithPath: "/cache"), base: base)

        #expect(environment["PATH"] == "/usr/bin")
        #expect(environment["NODE_OPTIONS"] == nil)
        #expect(environment["NPM_CONFIG_PREFIX"] == nil)
        #expect(environment["npm_config_prefix"] == nil)
        #expect(environment["PREFIX"] == nil)
        #expect(environment["npm_config_cache"] == "/cache")
        #expect(environment["npm_config_fund"] == "false")
        #expect(environment["npm_config_audit"] == "false")
        #expect(environment["npm_config_update_notifier"] == "false")

        let verification = PiInstallRunner.verificationEnvironment(base: base)
        #expect(verification["CI"] == "1")
        #expect(verification["TERM"] == "dumb")
        #expect(verification["NODE_OPTIONS"] == nil)
    }

    private func makeManager(
        paths: PiRuntimePaths,
        settings: SettingsRepository? = nil,
        runner: FakeCommandRunner = FakeCommandRunner.reportingVersionFromEntryPath
    ) -> PiRuntimeManager {
        PiRuntimeManager(paths: paths, settings: settings, runner: runner) {
            BundledNode(nodeExecutable: URL(fileURLWithPath: "/fake/node"), npmCLI: URL(fileURLWithPath: "/fake/npm-cli.js"))
        }
    }

    private func installFakeEntry(_ version: String, paths: PiRuntimePaths) throws {
        let entry = paths.piEntry(for: version)
        try FileManager.default.createDirectory(at: entry.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: entry.path, contents: nil)
    }

    private func writePointer(_ pointer: CurrentPointer, paths: PiRuntimePaths) throws {
        try FileManager.default.createDirectory(
            at: paths.currentPointerFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(pointer).write(to: paths.currentPointerFile)
    }

    private func readPointer(paths: PiRuntimePaths) throws -> CurrentPointer {
        try JSONDecoder().decode(CurrentPointer.self, from: Data(contentsOf: paths.currentPointerFile))
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct FakeCommandRunner: CommandRunning {
    let handler: @Sendable ([String]) -> CommandResult?

    init(handler: @escaping @Sendable ([String]) -> CommandResult?) {
        self.handler = handler
    }

    // Echoes the `<version>` path component so `--version` matches whichever entry is checked.
    static let reportingVersionFromEntryPath = FakeCommandRunner { arguments in
        let components = arguments.first.map { URL(fileURLWithPath: $0).pathComponents } ?? []
        guard let index = components.firstIndex(of: "versions"), components.indices.contains(index + 1) else {
            return .ok(stdout: "")
        }
        return .ok(stdout: components[index + 1])
    }

    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration?,
        cancellation: CommandCancellation?
    ) -> CommandResult? {
        handler(arguments)
    }
}

private final class CallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []

    var arguments: [[String]] {
        lock.withLock { recorded }
    }

    func record(_ arguments: [String]) {
        lock.withLock { recorded.append(arguments) }
    }
}

private extension CommandResult {
    static func ok(stdout: String) -> CommandResult {
        CommandResult(exitCode: 0, stdout: stdout, stderr: "", timedOut: false)
    }
}
