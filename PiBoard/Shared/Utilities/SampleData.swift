import Foundation

// Prototype-only in-memory fixtures for the M0 board UI; no persistence behind this yet.
enum SampleData {
    static let myAppProject = Project(
        id: UUID(),
        name: "My App",
        path: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Developer/my-app"),
        createdAt: Date(timeIntervalSinceNow: -86_400 * 14),
        updatedAt: Date(timeIntervalSinceNow: -3_600)
    )

    static let websiteProject = Project(
        id: UUID(),
        name: "Website",
        path: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Developer/website"),
        createdAt: Date(timeIntervalSinceNow: -86_400 * 7),
        updatedAt: Date(timeIntervalSinceNow: -7_200)
    )

    // Path intentionally does not exist, so the board's missing-path banner has something to show.
    static let apiProject = Project(
        id: UUID(),
        name: "API",
        path: URL(fileURLWithPath: "/tmp/piboard-sample-missing/api"),
        createdAt: Date(timeIntervalSinceNow: -86_400 * 3),
        updatedAt: Date(timeIntervalSinceNow: -86_400)
    )

    static let projects: [Project] = [myAppProject, websiteProject, apiProject]

    private static let runningTaskID = UUID()
    private static let exitedTaskID = UUID()
    private static let worktreeTaskID = UUID()

    static let tasks: [BoardTask] = {
        var tasks: [BoardTask] = []

        let backlogTitles = [
            ("Add dark mode toggle", "Add a dark mode toggle to the settings screen."),
            ("Fix sidebar scroll jitter", "Investigate and fix the scroll jitter in the sidebar on resize."),
            ("Write onboarding copy", "Draft onboarding copy for first-run experience."),
        ]
        for (index, pair) in backlogTitles.enumerated() {
            tasks.append(
                BoardTask(
                    id: UUID(),
                    projectId: myAppProject.id,
                    title: pair.0,
                    prompt: pair.1,
                    status: .backlog,
                    position: index,
                    piSessionId: nil,
                    runContext: nil,
                    worktreePath: nil,
                    worktreeBranch: nil,
                    createdAt: Date(timeIntervalSinceNow: -86_400 * Double(index + 1)),
                    updatedAt: Date(timeIntervalSinceNow: -3_600 * Double(index + 1))
                )
            )
        }

        tasks.append(
            BoardTask(
                id: runningTaskID,
                projectId: myAppProject.id,
                title: "Refactor networking layer",
                prompt: "Extract the networking layer into a dedicated module with testable protocols.",
                status: .inProgress,
                position: 0,
                piSessionId: UUID(),
                runContext: .current,
                worktreePath: nil,
                worktreeBranch: nil,
                createdAt: Date(timeIntervalSinceNow: -86_400 * 2),
                updatedAt: Date(timeIntervalSinceNow: -600)
            )
        )

        tasks.append(
            BoardTask(
                id: worktreeTaskID,
                projectId: myAppProject.id,
                title: "Fix auth token refresh",
                prompt: "Auth tokens are not refreshed before expiry; add a refresh check before each request.",
                status: .inProgress,
                position: 1,
                piSessionId: nil,
                runContext: .worktree,
                worktreePath: myAppProject.path.appendingPathComponent(".piboard/worktrees/fix-auth"),
                worktreeBranch: "piboard/3f2a-fix-auth",
                createdAt: Date(timeIntervalSinceNow: -86_400),
                updatedAt: Date(timeIntervalSinceNow: -1_800)
            )
        )

        let doneTitles = [
            ("Set up CI pipeline", "Configure CI to run build and tests on every push."),
            ("Migrate to Swift 6 concurrency", "Adopt strict concurrency checking across the codebase."),
            ("Add project icon", "Design and add an app icon."),
        ]
        for (index, pair) in doneTitles.enumerated() {
            let id = index == 0 ? exitedTaskID : UUID()
            tasks.append(
                BoardTask(
                    id: id,
                    projectId: myAppProject.id,
                    title: pair.0,
                    prompt: pair.1,
                    status: .done,
                    position: index,
                    piSessionId: index == 0 ? UUID() : nil,
                    runContext: index == 0 ? .current : nil,
                    worktreePath: nil,
                    worktreeBranch: nil,
                    createdAt: Date(timeIntervalSinceNow: -86_400 * Double(index + 4)),
                    updatedAt: Date(timeIntervalSinceNow: -86_400 * Double(index + 1))
                )
            )
        }

        tasks.append(
            BoardTask(
                id: UUID(),
                projectId: websiteProject.id,
                title: "Update landing page hero",
                prompt: "Replace the hero image and update the copy for the new release.",
                status: .backlog,
                position: 0,
                piSessionId: nil,
                runContext: nil,
                worktreePath: nil,
                worktreeBranch: nil,
                createdAt: Date(timeIntervalSinceNow: -86_400 * 5),
                updatedAt: Date(timeIntervalSinceNow: -86_400 * 2)
            )
        )
        tasks.append(
            BoardTask(
                id: UUID(),
                projectId: websiteProject.id,
                title: "Fix mobile nav overflow",
                prompt: "The mobile nav menu overflows on small screens.",
                status: .inProgress,
                position: 0,
                piSessionId: nil,
                runContext: .current,
                worktreePath: nil,
                worktreeBranch: nil,
                createdAt: Date(timeIntervalSinceNow: -86_400 * 3),
                updatedAt: Date(timeIntervalSinceNow: -3_600 * 4)
            )
        )

        return tasks
    }()

    static let runtimeStates: [UUID: TaskRuntimeState] = [
        runningTaskID: .running,
        exitedTaskID: .exited(1),
    ]
}
