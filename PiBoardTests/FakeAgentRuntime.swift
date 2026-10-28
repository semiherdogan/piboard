import Foundation
import Observation
@testable import PiBoard

/// Stands in for an installed agent in tests: status and entry are set directly, nothing touches disk.
@MainActor
@Observable
final class FakeAgentRuntime: AgentRuntime {
    let package: AgentPackage
    var status: AgentRuntimeStatus
    var activeVersion: String?
    var entry: URL
    @ObservationIgnored var versionsInUse: @MainActor () -> Set<String> = { [] }
    private(set) var refreshCount = 0

    init(
        package: AgentPackage = .pi,
        status: AgentRuntimeStatus = .ready(version: "0.0.0"),
        entry: URL = URL(fileURLWithPath: "/tmp/fake-entry.js")
    ) {
        self.package = package
        self.status = status
        self.entry = entry
        if case .ready(let version) = status {
            activeVersion = version
        }
    }

    func activeEntry() throws -> (version: String, entry: URL) {
        guard case .ready(let version) = status else { throw PiRuntimeManagerError.noActiveVersion }
        return (version, entry)
    }

    func refresh() {
        refreshCount += 1
    }
}
