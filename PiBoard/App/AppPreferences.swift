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
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
