import Testing
@testable import PiBoard

struct PTYRuntimeStateTests {
    @Test func isRunningOnlyTrueForRunning() {
        #expect(PTYRuntimeState.notStarted.isRunning == false)
        #expect(PTYRuntimeState.running.isRunning == true)
        #expect(PTYRuntimeState.exited(0).isRunning == false)
    }

    @Test func exitCodeExtractsAssociatedValue() {
        #expect(PTYRuntimeState.notStarted.exitCode == nil)
        #expect(PTYRuntimeState.running.exitCode == nil)
        #expect(PTYRuntimeState.exited(3).exitCode == 3)
        #expect(PTYRuntimeState.exited(nil).exitCode == nil)
    }
}
