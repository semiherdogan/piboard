import Foundation
@testable import PiBoard

final class FakeHookServer: HookServing, @unchecked Sendable {
    static let port: UInt16 = 4242

    private let lock = NSLock()
    private var storedHandler: (@Sendable (String, Data) -> Void)?
    private var starts = 0
    private var stops = 0
    var startError: (any Error)?

    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }
    var handler: (@Sendable (String, Data) -> Void)? { lock.withLock { storedHandler } }

    func start(handler: @escaping @Sendable (_ path: String, _ body: Data) -> Void) async throws -> UInt16 {
        if let startError { throw startError }
        lock.withLock {
            starts += 1
            storedHandler = handler
        }
        return Self.port
    }

    func stop() {
        lock.withLock { stops += 1 }
    }
}
