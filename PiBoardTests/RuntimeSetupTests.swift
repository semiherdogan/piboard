import Testing
@testable import PiBoard
import Foundation

private let httpsScheme = "https"
private let insecureURL = URL(string: "http://example.com/install.sh")!

private struct FailingDownloader: ScriptDownloading {
    let error: RuntimeSetupError

    func download(_ url: URL) async throws -> URL {
        throw error
    }
}

private let exitThreeScript = "exit 3\n"
private let sleepingScript = "exec sleep 60\n"
private let scriptFileName = "setup-script"
private let scriptExitCode: Int32 = 3
private let waitStepMilliseconds = 10
private let waitStepLimit = 1500

/// Writes a local script into its own fresh directory, like the real downloader does.
private final class LocalScriptDownloader: ScriptDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private var lastDirectory: URL?
    let body: String

    init(body: String) {
        self.body = body
    }

    var directory: URL {
        lock.withLock { lastDirectory! }
    }

    func download(_ url: URL) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        lock.withLock { lastDirectory = directory }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent(scriptFileName)
        try Data(body.utf8).write(to: script)
        return script
    }
}

private struct HangingDownloader: ScriptDownloading {
    func download(_ url: URL) async throws -> URL {
        try await Task.sleep(for: .seconds(60))
        throw RuntimeSetupError.invalidResponse
    }
}

@MainActor
final class FinishCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}

@MainActor
struct RuntimeSetupTests {
    private func makeRunner(_ downloader: any ScriptDownloading) -> RuntimeSetupRunner {
        RuntimeSetupRunner(makeSession: { PTYSession() }, downloader: downloader)
    }

    private func isRunning(_ runner: RuntimeSetupRunner) -> Bool {
        if case .running = runner.state { return true }
        return false
    }

    private func isFinished(_ runner: RuntimeSetupRunner) -> Bool {
        if case .finished = runner.state { return true }
        return false
    }

    @Test func installRunsToFinishedWithTheScriptExitCode() async throws {
        let downloader = LocalScriptDownloader(body: exitThreeScript)
        let runner = makeRunner(downloader)
        let finishes = FinishCounter()

        runner.start(.install, package: .claudeCode, executable: nil) { finishes.increment() }
        try await waitUntil { isFinished(runner) && finishes.count > 0 }

        guard case .finished(_, let exitCode, let wasCancelled) = runner.state else {
            Issue.record("expected finished, got \(runner.state)")
            return
        }
        #expect(exitCode == scriptExitCode)
        #expect(!wasCancelled)
        #expect(finishes.count == 1)
        #expect(!FileManager.default.fileExists(atPath: downloader.directory.path))
    }

    @Test func dismissDuringARunCallsOnFinishOnceAndAllowsANewStart() async throws {
        let first = FinishCounter()
        let runner = makeRunner(LocalScriptDownloader(body: sleepingScript))
        runner.start(.install, package: .claudeCode, executable: nil) { first.increment() }
        try await waitUntil { isRunning(runner) }

        runner.dismiss()
        try await waitUntil { first.count > 0 }

        #expect(runner.isIdle)
        #expect(first.count == 1)
        let second = FinishCounter()
        runner.start(.install, package: .claudeCode, executable: nil) { second.increment() }
        try await waitUntil { isRunning(runner) }
        #expect(isRunning(runner))
        runner.dismiss()
        try await waitUntil { second.count > 0 }
        #expect(first.count == 1)
        #expect(second.count == 1)
    }

    @Test func staleRunCompletionDoesNotOverwriteANewerRun() async throws {
        let first = FinishCounter()
        let runner = makeRunner(LocalScriptDownloader(body: sleepingScript))
        runner.start(.install, package: .claudeCode, executable: nil) { first.increment() }
        try await waitUntil { isRunning(runner) }
        runner.dismiss()
        runner.start(.install, package: .claudeCode, executable: nil) {}
        try await waitUntil { isRunning(runner) }
        guard case .running(let newer) = runner.state else {
            Issue.record("expected running, got \(runner.state)")
            return
        }

        try await waitUntil { first.count > 0 }

        guard case .running(let current) = runner.state else {
            Issue.record("stale completion replaced the state: \(runner.state)")
            return
        }
        #expect(current.id == newer.id)
        runner.dismiss()
    }

    @Test func cancelDuringARunReportsAStoppedRun() async throws {
        let runner = makeRunner(LocalScriptDownloader(body: sleepingScript))
        runner.start(.install, package: .claudeCode, executable: nil) {}
        try await waitUntil { isRunning(runner) }

        runner.cancel()
        try await waitUntil { isFinished(runner) }

        guard case .finished(_, _, let wasCancelled) = runner.state else {
            Issue.record("expected finished, got \(runner.state)")
            return
        }
        #expect(wasCancelled)
    }

    @Test func cancelDuringDownloadReturnsToIdle() async throws {
        let runner = makeRunner(HangingDownloader())
        let finishes = FinishCounter()
        runner.start(.install, package: .claudeCode, executable: nil) { finishes.increment() }
        #expect(runner.state == .downloading(.claudeCode))

        runner.cancelDownload()
        try await Task.sleep(for: .milliseconds(50))

        #expect(runner.isIdle)
        #expect(finishes.count == 0)
    }

    @Test func stopForQuitTerminatesTheRunAndRemovesTheScript() async throws {
        let downloader = LocalScriptDownloader(body: sleepingScript)
        let runner = makeRunner(downloader)
        runner.start(.install, package: .claudeCode, executable: nil) {}
        try await waitUntil { isRunning(runner) }
        #expect(runner.isBusy)

        runner.stopForQuit()

        #expect(runner.isIdle)
        #expect(!FileManager.default.fileExists(atPath: downloader.directory.path))
    }

    @Test func openCodeRecipe() throws {
        let recipe = try #require(AgentPackage.opencode.recipe)

        #expect(recipe.scriptURL.scheme == httpsScheme)
        #expect(recipe.interpreter == URL(fileURLWithPath: "/bin/bash"))
        #expect(recipe.scriptArguments == ["--no-modify-path"])
        #expect(recipe.updateArguments == ["upgrade"])
    }

    @Test func claudeCodeRecipe() throws {
        let recipe = try #require(AgentPackage.claudeCode.recipe)

        #expect(recipe.scriptURL.scheme == httpsScheme)
        #expect(recipe.interpreter == URL(fileURLWithPath: "/bin/bash"))
        #expect(recipe.scriptArguments.isEmpty)
        #expect(recipe.updateArguments == ["update"])
    }

    @Test func managedPiHasNoRecipe() {
        #expect(AgentPackage.pi.recipe == nil)
    }

    @Test func displayNamesMatchTheAgentTitles() {
        #expect(AgentPackage.opencode.displayName == AgentKind.opencode.title)
        #expect(AgentPackage.claudeCode.displayName == AgentKind.claudeCode.title)
    }

    @Test func installRunsTheScriptThroughTheInterpreter() throws {
        let recipe = try #require(AgentPackage.opencode.recipe)
        let script = URL(fileURLWithPath: "/tmp/piboard-script/setup-script")

        let command = RuntimeSetupCommand.install(recipe: recipe, script: script)

        #expect(command.executable == recipe.interpreter)
        #expect(command.arguments == [script.path, "--no-modify-path"])
    }

    @Test func updateRunsTheExecutableWithItsUpdateArguments() throws {
        let recipe = try #require(AgentPackage.claudeCode.recipe)
        let executable = URL(fileURLWithPath: "/fake/bin/claude")

        let command = RuntimeSetupCommand.update(recipe: recipe, executable: executable)

        #expect(command.executable == executable)
        #expect(command.arguments == ["update"])
    }

    @Test func downloaderRejectsNonHTTPSWithoutTouchingTheNetwork() async {
        await #expect(throws: RuntimeSetupError.insecureURL(insecureURL)) {
            _ = try await ScriptDownloader().download(insecureURL)
        }
    }

    @Test func failedDownloadMovesRunnerToFailedWithTheReason() async throws {
        let error = RuntimeSetupError.httpStatus(404)
        let runner = RuntimeSetupRunner(makeSession: { PTYSession() }, downloader: FailingDownloader(error: error))

        runner.start(.install, package: .opencode, executable: nil) {}
        try await waitUntil { !runner.isIdle && runner.state != .downloading(.opencode) }

        #expect(runner.state == .failed(.opencode, action: .install, reason: error.localizedDescription))
    }

    @Test func updateWithoutExecutableFails() {
        let runner = RuntimeSetupRunner(makeSession: { PTYSession() }, downloader: OfflineScriptDownloader())

        runner.start(.update, package: .claudeCode, executable: nil) {}

        let reason = RuntimeSetupError.missingExecutable.localizedDescription
        #expect(runner.state == .failed(.claudeCode, action: .update, reason: reason))
    }

    @Test func managedPackageFailsWithoutARecipe() {
        let runner = RuntimeSetupRunner(makeSession: { PTYSession() }, downloader: OfflineScriptDownloader())

        runner.start(.install, package: .pi, executable: nil) {}

        let reason = RuntimeSetupError.missingRecipe.localizedDescription
        #expect(runner.state == .failed(.pi, action: .install, reason: reason))
    }

    @Test func dismissReturnsToIdleAndAllowsANewStart() {
        let runner = RuntimeSetupRunner(makeSession: { PTYSession() }, downloader: OfflineScriptDownloader())
        runner.start(.update, package: .claudeCode, executable: nil) {}
        #expect(!runner.isIdle)

        runner.dismiss()

        #expect(runner.isIdle)
    }

    @Test func anyNonIdleStatePresentsTheSheet() {
        let runner = RuntimeSetupRunner(makeSession: { PTYSession() }, downloader: OfflineScriptDownloader())
        #expect(!runner.presentsSheet)

        runner.start(.update, package: .claudeCode, executable: nil) {}
        #expect(runner.presentsSheet)

        runner.dismiss()
        #expect(!runner.presentsSheet)
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        for _ in 0..<waitStepLimit {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(waitStepMilliseconds))
        }
        if !condition() {
            Issue.record("waitUntil timed out", sourceLocation: sourceLocation)
        }
    }
}
