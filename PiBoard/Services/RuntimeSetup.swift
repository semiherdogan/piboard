import Foundation
import Observation

private let httpsScheme = "https"
private let successStatusCodes = 200..<300
private let downloadedScriptName = "setup-script"
private let commandSeparator = " "

enum RuntimeSetupAction: Equatable, Sendable {
    case install
    case update
}

enum RuntimeSetupError: LocalizedError, Equatable {
    case insecureURL(URL)
    case httpStatus(Int)
    case invalidResponse
    case missingExecutable
    case missingRecipe
    case networkDisabled
    case launchFailed

    var errorDescription: String? {
        switch self {
        case .insecureURL(let url): "Refusing to download \(url.absoluteString): only https is allowed."
        case .httpStatus(let code): "The download failed with HTTP status \(code)."
        case .invalidResponse: "The download did not return an HTTP response."
        case .missingExecutable: "No installed executable was found to update."
        case .missingRecipe: "This agent has no installer."
        case .networkDisabled: "Downloads are disabled in this build."
        case .launchFailed: "The setup process could not be started."
        }
    }
}

/// Builds the process invocations; pure so the argument lists are testable without a process.
enum RuntimeSetupCommand {
    typealias Invocation = (executable: URL, arguments: [String])

    static func install(recipe: UserInstallRecipe, script: URL) -> Invocation {
        (recipe.interpreter, [script.path] + recipe.scriptArguments)
    }

    static func update(recipe: UserInstallRecipe, executable: URL) -> Invocation {
        (executable, recipe.updateArguments)
    }

    static func display(_ invocation: Invocation) -> String {
        ([invocation.executable.path] + invocation.arguments).joined(separator: commandSeparator)
    }
}

protocol ScriptDownloading: Sendable {
    /// Returns the downloaded file, alone in a directory created for this download.
    func download(_ url: URL) async throws -> URL
}

struct ScriptDownloader: ScriptDownloading {
    func download(_ url: URL) async throws -> URL {
        guard url.scheme?.lowercased() == httpsScheme else {
            throw RuntimeSetupError.insecureURL(url)
        }
        let (temporary, response) = try await URLSession.shared.download(from: url)
        let files = FileManager.default
        do {
            guard let http = response as? HTTPURLResponse else { throw RuntimeSetupError.invalidResponse }
            guard successStatusCodes.contains(http.statusCode) else { throw RuntimeSetupError.httpStatus(http.statusCode) }
            // A fresh directory per download keeps an untrusted script away from anything else on disk.
            let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(downloadedScriptName)
            do {
                try files.moveItem(at: temporary, to: destination)
            } catch {
                try? files.removeItem(at: directory)
                throw error
            }
            return destination
        } catch {
            try? files.removeItem(at: temporary)
            throw error
        }
    }
}

/// Used by tests so no run reaches the network.
struct OfflineScriptDownloader: ScriptDownloading {
    func download(_ url: URL) async throws -> URL {
        throw RuntimeSetupError.networkDisabled
    }
}

struct RuntimeSetupRun: Identifiable, Equatable {
    let id = UUID()
    let package: AgentPackage
    let action: RuntimeSetupAction
    let session: PTYSession
    /// For display only; never executed as a string.
    let command: String

    static func == (lhs: RuntimeSetupRun, rhs: RuntimeSetupRun) -> Bool {
        lhs.id == rhs.id
    }
}

/// Runs the vendor installer or self-update of one user-installed agent at a time, in a pty so
/// prompts and progress reach the user.
@MainActor
@Observable
final class RuntimeSetupRunner {
    enum State: Equatable {
        case idle
        case downloading(AgentPackage)
        case running(RuntimeSetupRun)
        /// The exit code is the decoded status, so a SIGTERM reads as 15; `wasCancelled` tells a user stop apart.
        case finished(RuntimeSetupRun, exitCode: Int32?, wasCancelled: Bool)
        case failed(AgentPackage, action: RuntimeSetupAction, reason: String)
    }

    private(set) var state: State = .idle

    var isBusy: Bool {
        switch state {
        case .downloading, .running: true
        case .idle, .finished, .failed: false
        }
    }

    var isIdle: Bool {
        state == .idle
    }

    /// Every non-idle state shows the one sheet, so a leftover run is never invisible.
    var presentsSheet: Bool {
        !isIdle
    }

    @ObservationIgnored private let makeSession: @MainActor () -> PTYSession
    @ObservationIgnored private let downloader: any ScriptDownloading
    @ObservationIgnored private let homeDirectory: URL
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var cancelledRunID: UUID?
    @ObservationIgnored private var activeScript: URL?

    init(
        makeSession: @escaping @MainActor () -> PTYSession,
        downloader: any ScriptDownloading,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.makeSession = makeSession
        self.downloader = downloader
        self.homeDirectory = homeDirectory
    }

    /// `executable` is required for update and ignored for install. `onFinish` runs after the
    /// process exits with any code, and is not called when the setup fails before it starts.
    func start(
        _ action: RuntimeSetupAction,
        package: AgentPackage,
        executable: URL?,
        onFinish: @escaping @MainActor () -> Void
    ) {
        guard isIdle else { return }
        guard let recipe = package.recipe else {
            fail(package, action, RuntimeSetupError.missingRecipe)
            return
        }
        switch action {
        case .install:
            state = .downloading(package)
            Diagnostics.runtime.info("downloading \(package.displayName, privacy: .public) installer")
            downloadTask = Task {
                do {
                    let script = try await downloader.download(recipe.scriptURL)
                    guard !Task.isCancelled else {
                        removeScript(script)
                        return
                    }
                    launch(
                        RuntimeSetupCommand.install(recipe: recipe, script: script),
                        action: action,
                        package: package,
                        script: script,
                        onFinish: onFinish
                    )
                } catch {
                    guard !Task.isCancelled else { return }
                    fail(package, action, error)
                }
            }
        case .update:
            guard let executable else {
                fail(package, action, RuntimeSetupError.missingExecutable)
                return
            }
            launch(
                RuntimeSetupCommand.update(recipe: recipe, executable: executable),
                action: action,
                package: package,
                script: nil,
                onFinish: onFinish
            )
        }
    }

    func cancel() {
        if case .running(let run) = state {
            cancelledRunID = run.id
            run.session.terminate()
        }
    }

    func cancelDownload() {
        guard case .downloading = state else { return }
        downloadTask?.cancel()
        downloadTask = nil
        state = .idle
    }

    func dismiss() {
        downloadTask?.cancel()
        downloadTask = nil
        if case .running(let run) = state {
            run.session.terminate()
        }
        state = .idle
    }

    /// Quit path: stop the process and remove the script now, since the exit wait may never run.
    func stopForQuit() {
        dismiss()
        if let activeScript { removeScript(activeScript) }
        activeScript = nil
    }

    private func launch(
        _ invocation: RuntimeSetupCommand.Invocation,
        action: RuntimeSetupAction,
        package: AgentPackage,
        script: URL?,
        onFinish: @escaping @MainActor () -> Void
    ) {
        let session = makeSession()
        let run = RuntimeSetupRun(
            package: package,
            action: action,
            session: session,
            command: RuntimeSetupCommand.display(invocation)
        )
        state = .running(run)
        activeScript = script
        session.start(executable: invocation.executable, arguments: invocation.arguments, currentDirectory: homeDirectory)
        // SwiftTerm returns silently when the fork fails and the session still reads as running.
        guard session.processID != nil else {
            if let script { removeScript(script) }
            activeScript = nil
            fail(package, action, RuntimeSetupError.launchFailed)
            return
        }
        Diagnostics.runtime.info("started \(String(describing: action), privacy: .public) for \(package.displayName, privacy: .public)")
        // Not stored: dismissing the sheet must not stop the wait, so onFinish still refreshes the runtime.
        Task {
            let exitCode = await session.waitForExit()
            if let script { removeScript(script) }
            Diagnostics.runtime.info("\(package.displayName, privacy: .public) setup exited with \(exitCode.map { String($0) } ?? "signal", privacy: .public)")
            if case .running(let current) = state, current.id == run.id {
                state = .finished(run, exitCode: exitCode, wasCancelled: cancelledRunID == run.id)
            }
            onFinish()
        }
    }

    private func fail(_ package: AgentPackage, _ action: RuntimeSetupAction, _ error: Error) {
        let reason = error.localizedDescription
        Diagnostics.runtime.error("\(package.displayName, privacy: .public) setup failed: \(reason, privacy: .public)")
        state = .failed(package, action: action, reason: reason)
    }

    private func removeScript(_ script: URL) {
        try? FileManager.default.removeItem(at: script.deletingLastPathComponent())
    }
}
