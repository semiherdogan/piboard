import Foundation
import Observation

// Composition root for services; populated as milestones land.
@MainActor
@Observable
final class AppEnvironment {
    var spikeSession: PTYSession?

    init() {}

    func spikeSessionOrCreate() -> PTYSession {
        if let spikeSession {
            return spikeSession
        }
        let session = PTYSession()
        session.startLoginShell(currentDirectory: FileManager.default.homeDirectoryForCurrentUser.path)
        spikeSession = session
        return session
    }
}
