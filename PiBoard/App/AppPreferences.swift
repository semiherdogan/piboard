import Foundation
import Observation

let defaultPlanFirstSuffix = "Önce sadece bir plan çıkar. Ben onayladıktan sonra koda başlayacağız."

@MainActor
@Observable
final class AppPreferences {
    private let settingsRepository: SettingsRepository

    var planFirstSuffix: String {
        didSet {
            guard planFirstSuffix != oldValue else { return }
            try? settingsRepository.set(.planFirstSuffix, value: planFirstSuffix)
        }
    }

    var planFirstEnabled: Bool {
        didSet {
            guard planFirstEnabled != oldValue else { return }
            try? settingsRepository.setBool(.planFirstEnabled, value: planFirstEnabled)
        }
    }

    var terminalFontName: String {
        didSet {
            guard terminalFontName != oldValue else { return }
            try? settingsRepository.set(.terminalFontName, value: terminalFontName)
        }
    }

    var terminalFontSize: Double {
        didSet {
            // Re-assigning the clamped value re-enters didSet once with an in-range value.
            let clamped = terminalFontSize.clamped(to: TerminalFontChoice.sizeRange)
            guard clamped == terminalFontSize else {
                terminalFontSize = clamped
                return
            }
            guard terminalFontSize != oldValue else { return }
            try? settingsRepository.setDouble(.terminalFontSize, value: terminalFontSize)
        }
    }

    var terminalLineHeightMultiplier: Double {
        didSet {
            let clamped = terminalLineHeightMultiplier.clamped(to: TerminalLineHeight.range)
            guard clamped == terminalLineHeightMultiplier else {
                terminalLineHeightMultiplier = clamped
                return
            }
            guard terminalLineHeightMultiplier != oldValue else { return }
            try? settingsRepository.setDouble(.terminalLineHeightMultiplier, value: terminalLineHeightMultiplier)
        }
    }

    var terminalCursorStyle: TerminalCursorStyleChoice {
        didSet {
            guard terminalCursorStyle != oldValue else { return }
            try? settingsRepository.set(.terminalCursorStyle, value: terminalCursorStyle.rawValue)
        }
    }

    var terminalScrollbackLines: Int {
        didSet {
            guard terminalScrollbackLines != oldValue else { return }
            try? settingsRepository.setInt(.terminalScrollbackLines, value: terminalScrollbackLines)
        }
    }

    var terminalOptionAsMeta: Bool {
        didSet {
            guard terminalOptionAsMeta != oldValue else { return }
            try? settingsRepository.setBool(.terminalOptionAsMeta, value: terminalOptionAsMeta)
        }
    }

    var changesPanelWidth: Double {
        didSet {
            let clamped = changesPanelWidth.clamped(to: ChangesPanelWidth.minimum...ChangesPanelWidth.maximum)
            guard clamped == changesPanelWidth else {
                changesPanelWidth = clamped
                return
            }
            guard changesPanelWidth != oldValue else { return }
            try? settingsRepository.setDouble(.changesPanelWidth, value: changesPanelWidth)
        }
    }

    var terminalDrawerHeight: Double {
        didSet {
            let clamped = terminalDrawerHeight.clamped(to: TerminalDrawerHeight.minimum...TerminalDrawerHeight.maximum)
            guard clamped == terminalDrawerHeight else {
                terminalDrawerHeight = clamped
                return
            }
            guard terminalDrawerHeight != oldValue else { return }
            try? settingsRepository.setDouble(.terminalDrawerHeight, value: terminalDrawerHeight)
        }
    }

    var preferredEditor: ExternalApp {
        didSet {
            guard preferredEditor != oldValue else { return }
            try? settingsRepository.set(.preferredEditor, value: preferredEditor.rawValue)
        }
    }

    var preferredTerminal: ExternalApp {
        didSet {
            guard preferredTerminal != oldValue else { return }
            try? settingsRepository.set(.preferredTerminal, value: preferredTerminal.rawValue)
        }
    }

    var keyboardShortcuts: [ShortcutAction: KeyboardShortcut] {
        didSet {
            guard keyboardShortcuts != oldValue else { return }
            // Keyed by raw value: a dictionary with enum keys would encode as a flat array.
            let stored = Dictionary(uniqueKeysWithValues: keyboardShortcuts.map { ($0.key.rawValue, $0.value) })
            guard let data = try? JSONEncoder().encode(stored), let json = String(data: data, encoding: .utf8) else { return }
            try? settingsRepository.set(.keyboardShortcuts, value: json)
        }
    }

    var promptTemplates: [PromptTemplate] {
        didSet {
            guard promptTemplates != oldValue else { return }
            guard let data = try? JSONEncoder().encode(promptTemplates), let json = String(data: data, encoding: .utf8) else { return }
            try? settingsRepository.set(.promptTemplates, value: json)
        }
    }

    var commitMessageModel: String {
        didSet {
            guard commitMessageModel != oldValue else { return }
            try? settingsRepository.set(.commitMessageModel, value: commitMessageModel)
        }
    }

    var commitMessageAgent: AgentKind {
        didSet {
            guard commitMessageAgent != oldValue else { return }
            try? settingsRepository.set(.commitMessageAgent, value: commitMessageAgent.rawValue)
        }
    }

    var claudeCommitMessageModel: String {
        didSet {
            guard claudeCommitMessageModel != oldValue else { return }
            try? settingsRepository.set(.claudeCommitMessageModel, value: claudeCommitMessageModel)
        }
    }

    /// One path per line, as typed in Settings.
    var headlessExtensionPaths: String {
        didSet {
            guard headlessExtensionPaths != oldValue else { return }
            try? settingsRepository.set(.headlessExtensionPaths, value: headlessExtensionPaths)
        }
    }

    /// Set by Don't Show Again on the board's showTerminalProgress banner.
    var terminalProgressHintDismissed: Bool {
        didSet {
            guard terminalProgressHintDismissed != oldValue else { return }
            try? settingsRepository.setBool(.terminalProgressHintDismissed, value: terminalProgressHintDismissed)
        }
    }

    /// Agents offered in the pickers. Always contains `AgentKind.default`.
    var enabledAgents: Set<AgentKind> {
        didSet {
            guard enabledAgents.contains(AgentKind.default) else {
                enabledAgents.insert(AgentKind.default)
                return
            }
            guard enabledAgents != oldValue else { return }
            // A disabled agent is no longer offered in Settings, so the stored choice must not keep driving commit messages.
            if !enabledAgents.contains(commitMessageAgent) {
                commitMessageAgent = AgentKind.default
            }
            let raw = enabledAgents.map(\.rawValue).sorted()
            guard let data = try? JSONEncoder().encode(raw), let json = String(data: data, encoding: .utf8) else { return }
            try? settingsRepository.set(.enabledAgents, value: json)
        }
    }

    var agentChoices: [AgentKind] {
        AgentKind.allCases.filter { enabledAgents.contains($0) }
    }

    var claudeHeadlessModel: String? {
        let model = claudeCommitMessageModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? nil : model
    }

    var headlessOptions: PiHeadlessOptions {
        let model = commitMessageModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let extensions = headlessExtensionPaths
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { ($0 as NSString).expandingTildeInPath }
        return PiHeadlessOptions(model: model.isEmpty ? nil : model, extensions: extensions)
    }

    func shortcut(for action: ShortcutAction) -> KeyboardShortcut? {
        keyboardShortcuts[action]
    }

    func setShortcut(_ shortcut: KeyboardShortcut?, for action: ShortcutAction) {
        keyboardShortcuts[action] = shortcut
    }

    static let defaultEditor = ExternalApp.vsCode
    static let defaultTerminal = ExternalApp.terminal

    init(database: Database) {
        let settingsRepository = SettingsRepository(database: database)
        self.settingsRepository = settingsRepository
        let storedSuffix = settingsRepository.get(.planFirstSuffix)
        planFirstSuffix = (storedSuffix?.isEmpty == false) ? storedSuffix! : defaultPlanFirstSuffix
        planFirstEnabled = settingsRepository.getBool(.planFirstEnabled) ?? false
        terminalFontName = settingsRepository.get(.terminalFontName) ?? TerminalFontChoice.systemMonospaced
        terminalFontSize = (settingsRepository.getDouble(.terminalFontSize) ?? TerminalFontChoice.defaultSize)
            .clamped(to: TerminalFontChoice.sizeRange)
        terminalLineHeightMultiplier = (settingsRepository.getDouble(.terminalLineHeightMultiplier) ?? TerminalLineHeight.defaultMultiplier)
            .clamped(to: TerminalLineHeight.range)
        terminalCursorStyle = settingsRepository.get(.terminalCursorStyle)
            .flatMap(TerminalCursorStyleChoice.init(rawValue:)) ?? .default
        let storedScrollback = settingsRepository.getInt(.terminalScrollbackLines)
        terminalScrollbackLines = storedScrollback.flatMap { TerminalScrollback.choices.contains($0) ? $0 : nil }
            ?? TerminalScrollback.defaultLines
        terminalOptionAsMeta = settingsRepository.getBool(.terminalOptionAsMeta) ?? TerminalOptionAsMeta.defaultValue
        changesPanelWidth = settingsRepository.getDouble(.changesPanelWidth)
            .map { $0.clamped(to: ChangesPanelWidth.minimum...ChangesPanelWidth.maximum) } ?? ChangesPanelWidth.defaultValue
        terminalDrawerHeight = settingsRepository.getDouble(.terminalDrawerHeight)
            .map { $0.clamped(to: TerminalDrawerHeight.minimum...TerminalDrawerHeight.maximum) } ?? TerminalDrawerHeight.defaultValue
        preferredEditor = settingsRepository.get(.preferredEditor).flatMap(ExternalApp.init(rawValue:)) ?? Self.defaultEditor
        preferredTerminal = settingsRepository.get(.preferredTerminal).flatMap(ExternalApp.init(rawValue:)) ?? Self.defaultTerminal
        keyboardShortcuts = Self.decodeShortcuts(settingsRepository.get(.keyboardShortcuts))
        promptTemplates = Self.decodeTemplates(settingsRepository.get(.promptTemplates))
        commitMessageModel = settingsRepository.get(.commitMessageModel) ?? ""
        headlessExtensionPaths = settingsRepository.get(.headlessExtensionPaths) ?? ""
        commitMessageAgent = settingsRepository.get(.commitMessageAgent).flatMap(AgentKind.init(rawValue:)) ?? AgentKind.default
        claudeCommitMessageModel = settingsRepository.get(.claudeCommitMessageModel) ?? ""
        terminalProgressHintDismissed = settingsRepository.getBool(.terminalProgressHintDismissed) ?? false
        enabledAgents = Self.decodeEnabledAgents(settingsRepository.get(.enabledAgents))
    }

    static func decodeEnabledAgents(_ json: String?) -> Set<AgentKind> {
        let all = Set(AgentKind.allCases)
        guard let data = json?.data(using: .utf8),
              let stored = try? JSONDecoder().decode([String].self, from: data)
        else { return all }
        // Unknown raw values (an agent removed in a later version) are dropped.
        let kinds = Set(stored.compactMap(AgentKind.init(rawValue:)))
        return kinds.isEmpty ? all : kinds.union([AgentKind.default])
    }

    private static func decodeTemplates(_ json: String?) -> [PromptTemplate] {
        guard let data = json?.data(using: .utf8),
              let templates = try? JSONDecoder().decode([PromptTemplate].self, from: data)
        else { return [] }
        return templates
    }

    private static func decodeShortcuts(_ json: String?) -> [ShortcutAction: KeyboardShortcut] {
        guard let data = json?.data(using: .utf8),
              let stored = try? JSONDecoder().decode([String: KeyboardShortcut].self, from: data)
        else { return [:] }
        // Unknown keys (an action removed in a later version) are dropped.
        return Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
            ShortcutAction(rawValue: key).map { ($0, value) }
        })
    }
}
