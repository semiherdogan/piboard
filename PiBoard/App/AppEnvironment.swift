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
        return startFreshSpikeSession()
    }

    func restartSpikeSession() -> PTYSession {
        if let spikeSession, spikeSession.state.isRunning {
            spikeSession.terminate()
        }
        return startFreshSpikeSession()
    }

    private func startFreshSpikeSession() -> PTYSession {
        let session = PTYSession()
        session.startLoginShell(currentDirectory: FileManager.default.homeDirectoryForCurrentUser.path)
        spikeSession = session
        return session
    }
}
