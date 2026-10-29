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
    static let changesPush = "changesPush"
    static let changesPullRequest = "changesPullRequest"
    static let sheetCancel = "sheetCancel"
    static let preparationStart = "preparationStart"
    static let preparationRunAnyway = "preparationRunAnyway"
    static let preparationResume = "preparationResume"
    static let preparationAgentPicker = "preparationAgentPicker"
    static let projectDefaultAgentPicker = "projectDefaultAgentPicker"
    static let openCodeRefresh = "openCodeRefresh"
    static let terminalStop = "terminalStop"
    static let terminalInterrupt = "terminalInterrupt"
    static let terminalResume = "terminalResume"
    static let terminalHost = "terminalHost"
    static let terminalStatus = "terminalStatus"
    static let confirmDestructive = "confirmDestructive"
    static let insertTemplate = "insertTemplate"
    static let commandPaletteField = "commandPaletteField"

    static let sidebarRowPrefix = "sidebarRow."
    static let taskCardPrefix = "taskCard."
    static let commandPaletteRowPrefix = "commandPaletteRow."

    static func sidebarRow(_ projectID: UUID) -> String {
        sidebarRowPrefix + projectID.uuidString
    }

    static func taskCard(_ taskID: UUID) -> String {
        taskCardPrefix + taskID.uuidString
    }

    static func commandPaletteRow(_ id: UUID) -> String {
        commandPaletteRowPrefix + id.uuidString
    }
}
