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
        guard let processes = environment?.processes, processes.activeSessionCount > 0 else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = quitAlertTitle
        alert.informativeText = Self.quitAlertMessage(activeSessionCount: processes.activeSessionCount)
        alert.addButton(withTitle: quitAlertStopButtonTitle)
        alert.addButton(withTitle: quitAlertCancelButtonTitle)

        guard let window = sender.keyWindow else {
            // A modal alert answers synchronously, so no deferred reply is needed.
            return Self.confirmQuit(response: alert.runModal(), processes: processes) ? .terminateNow : .terminateCancel
        }
        alert.beginSheetModal(for: window) { response in
            NSApp.reply(toApplicationShouldTerminate: Self.confirmQuit(response: response, processes: processes))
        }
        return .terminateLater
    }

    private static func confirmQuit(response: NSApplication.ModalResponse, processes: PiProcessManager) -> Bool {
        let shouldQuit = response == .alertFirstButtonReturn
        if shouldQuit {
            processes.stopAll()
        }
        return shouldQuit
    }

    private static func quitAlertMessage(activeSessionCount: Int) -> String {
        "\(activeSessionCount) Pi session(s) are still running. Quitting stops them. Tasks stay In Progress and can be resumed later."
    }
}
