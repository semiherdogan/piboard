import Foundation
import Synchronization
@testable import PiBoard

final class StubCommandRunner: CommandRunning, Sendable {
    private let handler: @Sendable () -> CommandResult?
    private let calls = Mutex(0)

    init(handler: @escaping @Sendable () -> CommandResult?) {
        self.handler = handler
    }

    var callCount: Int { calls.withLock { $0 } }

    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration?,
        cancellation: CommandCancellation?
    ) -> CommandResult? {
        calls.withLock { $0 += 1 }
        return handler()
    }
}
