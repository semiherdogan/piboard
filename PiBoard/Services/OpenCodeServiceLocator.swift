import Foundation

/// Finds the user's shared OpenCode background server and its password. Read-only: the password
/// file belongs to OpenCode.
enum OpenCodeServiceLocator {
    static let statusArguments = ["service", "status"]
    static let startArguments = ["service", "start"]
    static let configFileName = "service.json"
    static let basicAuthUser = "opencode"
    static let commandTimeout: Duration = .seconds(15)
    private static let passwordKey = "password"
    private static let configDirectoryComponents = [".config", "opencode"]
    private static let supportedSchemes: Set<String> = ["http", "https"]

    /// `opencode service status` prints the URL on its first line, or nothing when the service is down.
    static func parseStatus(_ output: String) -> URL? {
        let firstLine = output
            .split(whereSeparator: \.isNewline)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let firstLine, !firstLine.isEmpty,
              let url = URL(string: firstLine),
              let scheme = url.scheme?.lowercased(), supportedSchemes.contains(scheme),
              url.host != nil
        else { return nil }
        return url
    }

    /// Runs status, and when it is empty runs start then status again.
    static func discover(runner: any CommandRunning, executable: URL, environment: [String: String]) -> URL? {
        if let url = status(runner: runner, executable: executable, environment: environment) {
            return url
        }
        _ = runner.run(
            executable: executable,
            arguments: startArguments,
            environment: environment,
            timeout: commandTimeout
        )
        return status(runner: runner, executable: executable, environment: environment)
    }

    static func readPassword(configDirectory: URL) -> String? {
        let file = configDirectory.appendingPathComponent(configFileName)
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let password = object[passwordKey] as? String, !password.isEmpty
        else { return nil }
        return password
    }

    static func defaultConfigDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        configDirectoryComponents.reduce(home) { $0.appendingPathComponent($1, isDirectory: true) }
    }

    private static func status(runner: any CommandRunning, executable: URL, environment: [String: String]) -> URL? {
        guard let result = runner.run(
            executable: executable,
            arguments: statusArguments,
            environment: environment,
            timeout: commandTimeout
        ), result.exitCode == 0, !result.timedOut else { return nil }
        return parseStatus(result.stdout)
    }
}
