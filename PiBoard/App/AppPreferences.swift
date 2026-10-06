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

    init(database: Database) {
        let settingsRepository = SettingsRepository(database: database)
        self.settingsRepository = settingsRepository
        let storedSuffix = settingsRepository.get(.planFirstSuffix)
        planFirstSuffix = (storedSuffix?.isEmpty == false) ? storedSuffix! : defaultPlanFirstSuffix
        planFirstEnabled = settingsRepository.getBool(.planFirstEnabled) ?? false
    }
}
