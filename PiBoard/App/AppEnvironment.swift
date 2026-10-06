import Foundation
import Observation

private let piSpikeSessionName = "PiBoard spike"

// Composition root for services; populated as milestones land.
@MainActor
@Observable
final class AppEnvironment {
    var spikeSession: PTYSession?
    let piRuntime = PiRuntimeManager()
    let board = BoardModel(sample: true)
    let processes = PiProcessManager()

    init() {
        piRuntime.refresh()
        processes.runtimeStates = SampleData.runtimeStates
    }

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

    func launchPiSpike(cwd: URL, prompt: String?) throws -> PTYSession {
        let node = try BundledNode.locate()
        let piEntry = try piRuntime.activeEntry()
        let command = PiLaunchCommand.build(
            node: node.nodeExecutable,
            piEntry: piEntry,
            mode: .newSession(sessionID: UUID(), name: piSpikeSessionName, initialPrompt: prompt),
            cwd: cwd
        )

        if let spikeSession, spikeSession.state.isRunning {
            spikeSession.terminate()
        }

        let session = PTYSession()
        session.start(command: command)
        spikeSession = session
        return session
    }
}
