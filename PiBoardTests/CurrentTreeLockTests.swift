import Foundation
import Testing
@testable import PiBoard

struct CurrentTreeLockTests {
    @Test func acquireSucceedsWhenUnowned() {
        var lock = PiProcessManager.CurrentTreeLock()
        let taskID = UUID()

        let acquired = lock.acquire(path: "/tmp/project", taskID: taskID)

        #expect(acquired)
        #expect(lock.owner(of: "/tmp/project") == taskID)
    }

    @Test func secondAcquireByOtherTaskFails() {
        var lock = PiProcessManager.CurrentTreeLock()
        let first = UUID()
        let second = UUID()

        let firstAcquired = lock.acquire(path: "/tmp/project", taskID: first)
        let secondAcquired = lock.acquire(path: "/tmp/project", taskID: second)

        #expect(firstAcquired)
        #expect(secondAcquired == false)
        #expect(lock.owner(of: "/tmp/project") == first)
    }

    @Test func releaseThenAcquireSucceeds() {
        var lock = PiProcessManager.CurrentTreeLock()
        let first = UUID()
        let second = UUID()

        _ = lock.acquire(path: "/tmp/project", taskID: first)
        lock.release(path: "/tmp/project")
        let acquired = lock.acquire(path: "/tmp/project", taskID: second)

        #expect(acquired)
        #expect(lock.owner(of: "/tmp/project") == second)
    }

    @Test func sameTaskReacquireIsFine() {
        var lock = PiProcessManager.CurrentTreeLock()
        let taskID = UUID()

        _ = lock.acquire(path: "/tmp/project", taskID: taskID)
        let reacquired = lock.acquire(path: "/tmp/project", taskID: taskID)

        #expect(reacquired)
        #expect(lock.owner(of: "/tmp/project") == taskID)
    }
}
