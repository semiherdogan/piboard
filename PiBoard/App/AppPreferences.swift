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
