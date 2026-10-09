import Foundation

/// Identifiers the UI tests use to find controls; keep in sync with PiBoardUITests.
enum AccessibilityID {
    static let inspectorToggle = "inspectorToggle"
    static let changesToggle = "changesToggle"
    static let newTask = "newTask"
    static let terminalDrawerToggle = "terminalDrawerToggle"
    static let projectOptions = "projectOptions"
    static let backToBoard = "backToBoard"
    static let boardTitle = "boardTitle"
    static let drawerHide = "drawerHide"
    static let drawerClose = "drawerClose"
    static let changesHide = "changesHide"
    static let sheetCancel = "sheetCancel"

    static let sidebarRowPrefix = "sidebarRow."
    static let taskCardPrefix = "taskCard."

    static func sidebarRow(_ projectID: UUID) -> String {
        sidebarRowPrefix + projectID.uuidString
    }

    static func taskCard(_ taskID: UUID) -> String {
        taskCardPrefix + taskID.uuidString
    }
}
