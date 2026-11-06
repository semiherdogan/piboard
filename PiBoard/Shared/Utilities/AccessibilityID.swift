import Foundation

/// Identifiers the UI tests use to find controls; keep in sync with PiBoardUITests.
enum AccessibilityID {
    static let taskDetailButton = "taskDetailButton"
    static let taskDetailDone = "taskDetailDone"
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
    static let migrationSummary = "migrationSummary"
    static let migrationStart = "migrationStart"
    static let migrationStartAnyway = "migrationStartAnyway"
    static let projectDefaultAgentPicker = "projectDefaultAgentPicker"
    static let openCodeRefresh = "openCodeRefresh"
    static let pigRefresh = "pigRefresh"
    static let claudeCodeRefresh = "claudeCodeRefresh"
    static let terminalStop = "terminalStop"
    static let terminalInterrupt = "terminalInterrupt"
    static let terminalResume = "terminalResume"
    static let terminalHost = "terminalHost"
    static let terminalStatus = "terminalStatus"
    static let terminalOpenIn = "terminalOpenIn"
    static let terminalCopyLastReply = "terminalCopyLastReply"
    static let confirmDestructive = "confirmDestructive"
    static let insertTemplate = "insertTemplate"
    static let commandPaletteField = "commandPaletteField"

    static let sidebarRowPrefix = "sidebarRow."
    static let taskCardPrefix = "taskCard."
    static let commandPaletteRowPrefix = "commandPaletteRow."
    static let agentTogglePrefix = "agentToggle."
    static let agentExecutablePathPrefix = "agentExecutablePath."
    static let agentExecutablePathClearPrefix = "agentExecutablePathClear."
    static let commitMessageAgentPicker = "commitMessageAgentPicker"
    static let commitGenerate = "commitGenerate"
    static let commitGenerateAgentPrefix = "commitGenerateAgent."
    static let runtimeInstallPrefix = "runtimeInstall."
    static let runtimeInstallConfirmPrefix = "runtimeInstallConfirm."
    static let runtimeUpdatePrefix = "runtimeUpdate."
    static let runtimeSetupCancel = "runtimeSetupCancel"
    static let runtimeSetupDownloadCancel = "runtimeSetupDownloadCancel"
    static let runtimeSetupClose = "runtimeSetupClose"
    static let runtimeSetupStatus = "runtimeSetupStatus"

    static func sidebarRow(_ projectID: UUID) -> String {
        sidebarRowPrefix + projectID.uuidString
    }

    static func taskCard(_ taskID: UUID) -> String {
        taskCardPrefix + taskID.uuidString
    }

    static func commandPaletteRow(_ id: UUID) -> String {
        commandPaletteRowPrefix + id.uuidString
    }

    static func agentToggle(_ kind: AgentKind) -> String {
        agentTogglePrefix + kind.rawValue
    }

    static func agentExecutablePath(_ kind: AgentKind) -> String {
        agentExecutablePathPrefix + kind.rawValue
    }

    static func agentExecutablePathClear(_ kind: AgentKind) -> String {
        agentExecutablePathClearPrefix + kind.rawValue
    }

    static func commitGenerateAgent(_ kind: AgentKind) -> String {
        commitGenerateAgentPrefix + kind.rawValue
    }

    static func runtimeInstall(_ package: AgentPackage) -> String {
        runtimeInstallPrefix + package.runtimeFolderName
    }

    static func runtimeInstallConfirm(_ package: AgentPackage) -> String {
        runtimeInstallConfirmPrefix + package.runtimeFolderName
    }

    static func runtimeUpdate(_ package: AgentPackage) -> String {
        runtimeUpdatePrefix + package.runtimeFolderName
    }
}
