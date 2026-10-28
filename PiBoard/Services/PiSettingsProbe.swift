import Foundation

/// Read-only look at the user's Pi settings file. PiBoard never writes it; this only decides
/// whether to tell the user about a setting PiBoard depends on.
struct PiSettingsProbe: Sendable {
    static let settingsFileName = "settings.json"
    private static let terminalKey = "terminal"
    private static let showTerminalProgressKey = "showTerminalProgress"

    let agentDirectory: URL

    init(agentDirectory: URL = PiSessionLocator.defaultAgentDirectory()) {
        self.agentDirectory = agentDirectory
    }

    var settingsFile: URL {
        agentDirectory.appendingPathComponent(Self.settingsFileName)
    }

    /// Nil when the file is missing or not JSON; Pi then runs on its default, which is off.
    func showsTerminalProgress() -> Bool? {
        guard let data = try? Data(contentsOf: settingsFile) else { return nil }
        return Self.showsTerminalProgress(in: data)
    }

    static func showsTerminalProgress(in data: Data) -> Bool? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let terminal = json[terminalKey] as? [String: Any]
        else { return nil }
        return terminal[showTerminalProgressKey] as? Bool
    }
}
