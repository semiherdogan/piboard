import AppKit
import UserNotifications

private let quitAlertTitle = "Quit PiBoard?"
private let quitAlertStopButtonTitle = "Stop and Quit"
private let quitAlertCancelButtonTitle = "Cancel"
private let quitSetupRunningNote = "An install or update is still running."

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
                || environment.runtimeSetup.isBusy
        else {
            return .terminateNow
        }
        let processes = environment.processes
        let shells = environment.shells
        let setup = environment.runtimeSetup

        let alert = NSAlert()
        alert.messageText = quitAlertTitle
        alert.informativeText = Self.quitAlertMessage(activeSessionCount: processes.activeSessionCount, shellCount: shells.runningCount, isSetupBusy: setup.isBusy)
        alert.addButton(withTitle: quitAlertStopButtonTitle)
        alert.addButton(withTitle: quitAlertCancelButtonTitle)

        guard let window = sender.keyWindow else {
            // A modal alert answers synchronously, so no deferred reply is needed.
            return Self.confirmQuit(response: alert.runModal(), processes: processes, shells: shells, setup: setup) ? .terminateNow : .terminateCancel
        }
        alert.beginSheetModal(for: window) { response in
            NSApp.reply(toApplicationShouldTerminate: Self.confirmQuit(response: response, processes: processes, shells: shells, setup: setup))
        }
        return .terminateLater
    }

    private static func confirmQuit(response: NSApplication.ModalResponse, processes: AgentProcessManager, shells: ShellSessions, setup: RuntimeSetupRunner) -> Bool {
        let shouldQuit = response == .alertFirstButtonReturn
        if shouldQuit {
            processes.stopAll()
            shells.stopAll()
            setup.stopForQuit()
        }
        return shouldQuit
    }

    private static func quitAlertMessage(activeSessionCount: Int, shellCount: Int, isSetupBusy: Bool) -> String {
        let resumeNote = "Tasks stay In Progress and can be resumed later."
        var parts: [String] = []
        if activeSessionCount > 0 || shellCount == 0 && !isSetupBusy {
            // Quit counts all agents together; the wording follows the default kind.
            let sessions = AgentStrings.sessionsStillRunning(count: activeSessionCount, .default)
            parts.append(shellCount > 0 ? "\(sessions) and \(shellCount) shell(s) are still running." : "\(sessions) are still running.")
        } else if shellCount > 0 {
            parts.append("\(shellCount) shell(s) are still running.")
        }
        if isSetupBusy { parts.append(quitSetupRunningNote) }
        parts.append("Quitting stops them.")
        if activeSessionCount > 0 { parts.append(resumeNote) }
        return parts.joined(separator: " ")
    }
}
