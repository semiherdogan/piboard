import Foundation
import UserNotifications

/// Used in hosted tests, where asking for notification permission would block on a system prompt.
struct NoNotifications: AgentNotifying {
    func requestAuthorization() async {}
    func notifyAgentFinished(taskTitle: String, projectName: String, target: AgentNotificationTarget) async {}
}

/// Identifies the task a delivered notification points at.
struct AgentNotificationTarget: Equatable, Sendable {
    let projectID: UUID
    let taskID: UUID
}

protocol AgentNotifying: Sendable {
    func requestAuthorization() async
    func notifyAgentFinished(taskTitle: String, projectName: String, target: AgentNotificationTarget) async
}

/// Posts "the agent finished" notifications and turns a click on one back into a target.
///
/// The target travels in `userInfo` rather than the identifier so the payload survives Notification
/// Centre round-trips without parsing a composite string.
struct AgentNotificationService: AgentNotifying {
    static let projectIDKey = "projectID"
    static let taskIDKey = "taskID"
    private static let categoryIdentifier = "agentFinished"
    private static let bodyFormat = "The agent finished working."

    // `UNUserNotificationCenter` is not `Sendable`, so it is resolved per call rather than stored.
    private var center: UNUserNotificationCenter { .current() }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func notifyAgentFinished(taskTitle: String, projectName: String, target: AgentNotificationTarget) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = taskTitle
        content.subtitle = projectName
        content.body = Self.bodyFormat
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [
            Self.projectIDKey: target.projectID.uuidString,
            Self.taskIDKey: target.taskID.uuidString,
        ]

        // A nil trigger delivers immediately; the identifier is per task so a second completion
        // replaces the first instead of stacking.
        let request = UNNotificationRequest(identifier: target.taskID.uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }

    /// Reads back what `notifyAgentFinished` wrote. Static and pure so the routing can be tested
    /// without constructing a `UNNotification`.
    static func target(from userInfo: [AnyHashable: Any]) -> AgentNotificationTarget? {
        guard let projectID = (userInfo[projectIDKey] as? String).flatMap(UUID.init(uuidString:)),
              let taskID = (userInfo[taskIDKey] as? String).flatMap(UUID.init(uuidString:))
        else { return nil }
        return AgentNotificationTarget(projectID: projectID, taskID: taskID)
    }
}
