import AppKit
import UserNotifications

private let quitAlertTitle = "Quit PiBoard?"
private let quitAlertStopButtonTitle = "Stop and Quit"
private let quitAlertCancelButtonTitle = "Cancel"

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var environment: AppEnvironment?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Must be set before any notification is delivered, or a click is dropped silently.
        UNUserNotificationCenter.current().delegate = self
    }

    /// A click on a delivered notification routes to the task it came from.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let target = AgentNotificationService.target(from: userInfo) else { return }
        await MainActor.run {
            environment?.open(target)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let environment,
              environment.processes.activeSessionCount > 0 || environment.shells.runningCount > 0
        else {
            return .terminateNow
        }
        let processes = environment.processes
        let shells = environment.shells

        let alert = NSAlert()
        alert.messageText = quitAlertTitle
        alert.informativeText = Self.quitAlertMessage(activeSessionCount: processes.activeSessionCount, shellCount: shells.runningCount)
        alert.addButton(withTitle: quitAlertStopButtonTitle)
        alert.addButton(withTitle: quitAlertCancelButtonTitle)

        guard let window = sender.keyWindow else {
            // A modal alert answers synchronously, so no deferred reply is needed.
            return Self.confirmQuit(response: alert.runModal(), processes: processes, shells: shells) ? .terminateNow : .terminateCancel
        }
        alert.beginSheetModal(for: window) { response in
            NSApp.reply(toApplicationShouldTerminate: Self.confirmQuit(response: response, processes: processes, shells: shells))
        }
        return .terminateLater
    }

    private static func confirmQuit(response: NSApplication.ModalResponse, processes: PiProcessManager, shells: ShellSessions) -> Bool {
        let shouldQuit = response == .alertFirstButtonReturn
        if shouldQuit {
            processes.stopAll()
            shells.stopAll()
        }
        return shouldQuit
    }

    private static func quitAlertMessage(activeSessionCount: Int, shellCount: Int) -> String {
        let resumeNote = "Tasks stay In Progress and can be resumed later."
        guard shellCount > 0 else {
            return "\(activeSessionCount) Pi session(s) are still running. Quitting stops them. \(resumeNote)"
        }
        return "\(activeSessionCount) Pi session(s) and \(shellCount) shell(s) are still running. Quitting stops them. \(resumeNote)"
    }
}
