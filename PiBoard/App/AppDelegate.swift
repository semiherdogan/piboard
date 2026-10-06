import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var environment: AppEnvironment?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        environment?.processes.stopAll()
        // A confirmation dialog for in-flight Pi sessions lands in a later milestone.
        return .terminateNow
    }
}
