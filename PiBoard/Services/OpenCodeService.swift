import Foundation

/// Finds the shared OpenCode server once, hands out a client, and forgets it after a 401 so the
/// password is re-read from service.json.
actor OpenCodeService {
    enum Failure: Error, Equatable, LocalizedError {
        case notInstalled
        case serviceUnavailable
        case passwordMissing

        var errorDescription: String? {
            switch self {
            case .notInstalled: "OpenCode is not installed."
            case .serviceUnavailable: "The OpenCode background service could not be started."
            case .passwordMissing: "The OpenCode service password was not found in ~/.config/opencode/service.json."
            }
        }
    }

    // The port changes when the service restarts, so a refused or lost connection means the cached URL is stale.
    private static let retriableURLErrorCodes: Set<URLError.Code> = [
        .cannotConnectToHost, .networkConnectionLost, .timedOut, .cannotFindHost,
    ]

    private let executable: @Sendable @MainActor () -> URL?
    private let runner: any CommandRunning
    private let environment: [String: String]
    private let configDirectory: URL
    private let urlSession: URLSession
    private var cached: OpenCodeClient?
    private var discovery: Task<OpenCodeClient, Error>?

    init(
        executable: @escaping @Sendable @MainActor () -> URL?,
        runner: any CommandRunning = ProcessCommandRunner(),
        environment: [String: String] = LaunchEnvironment.shared.values,
        configDirectory: URL = OpenCodeServiceLocator.defaultConfigDirectory(),
        urlSession: URLSession = .shared
    ) {
        self.executable = executable
        self.runner = runner
        self.environment = environment
        self.configDirectory = configDirectory
        self.urlSession = urlSession
    }

    func client() async throws -> OpenCodeClient {
        if let cached {
            return cached
        }
        let task = discovery ?? Task { try await discover() }
        discovery = task
        do {
            let client = try await task.value
            cached = client
            discovery = nil
            return client
        } catch {
            discovery = nil
            throw error
        }
    }

    private func discover() async throws -> OpenCodeClient {
        guard let binary = await executable() else {
            throw Failure.notInstalled
        }
        let runner = runner
        let environment = environment
        // Blocking: runs `opencode service status`, and `start` when the service is down.
        let baseURL = await Task.detached(priority: .utility) {
            OpenCodeServiceLocator.discover(runner: runner, executable: binary, environment: environment)
        }.value
        guard let baseURL else {
            throw Failure.serviceUnavailable
        }
        let configDirectory = configDirectory
        let password = await Task.detached(priority: .utility) {
            OpenCodeServiceLocator.readPassword(configDirectory: configDirectory)
        }.value
        guard let password else {
            throw Failure.passwordMissing
        }
        return OpenCodeClient(baseURL: baseURL, password: password, session: urlSession)
    }

    private static func isStaleClientError(_ error: Error) -> Bool {
        if let clientError = error as? OpenCodeClientError, clientError == .unauthorized {
            return true
        }
        if let urlError = error as? URLError {
            return retriableURLErrorCodes.contains(urlError.code)
        }
        return false
    }

    func invalidate() {
        cached = nil
        discovery = nil
    }

    /// Runs `body` and retries once with a fresh client after `.unauthorized` or a connection failure.
    func withClient<T: Sendable>(_ body: @Sendable (OpenCodeClient) async throws -> T) async throws -> T {
        do {
            return try await body(client())
        } catch where Self.isStaleClientError(error) {
            invalidate()
            return try await body(client())
        }
    }
}
