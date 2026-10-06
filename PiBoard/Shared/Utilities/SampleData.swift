import Foundation

// Fixtures for tests and previews, seeded through BoardModel's public API so they
// exercise the same persistence path as the real app. No runtime-state fixtures here;
// PiProcessManager owns that state.
@MainActor
enum SampleData {
    static func seed(into model: BoardModel) {
        let home = FileManager.default.homeDirectoryForCurrentUser

        model.addProject(name: "My App", path: home.appendingPathComponent("Developer/my-app"))
        guard let myApp = model.projects.first(where: { $0.name == "My App" }) else { return }

        model.addProject(name: "Website", path: home.appendingPathComponent("Developer/website"))
        guard let website = model.projects.first(where: { $0.name == "Website" }) else { return }

        // Path intentionally does not exist, so the board's missing-path banner has something to show.
        model.addProject(name: "API", path: URL(fileURLWithPath: "/tmp/piboard-sample-missing/api"))

        seedMyAppTasks(into: model, projectID: myApp.id)
        seedWebsiteTasks(into: model, projectID: website.id)
    }

    private static func seedMyAppTasks(into model: BoardModel, projectID: UUID) {
        let backlogTitles = [
            ("Add dark mode toggle", "Add a dark mode toggle to the settings screen."),
            ("Fix sidebar scroll jitter", "Investigate and fix the scroll jitter in the sidebar on resize."),
            ("Write onboarding copy", "Draft onboarding copy for first-run experience."),
        ]
        for pair in backlogTitles {
            model.addTask(title: pair.0, prompt: pair.1, to: projectID)
        }

        model.addTask(
            title: "Refactor networking layer",
            prompt: "Extract the networking layer into a dedicated module with testable protocols.",
            to: projectID
        )
        if let task = model.tasks(for: projectID, status: .backlog).first(where: { $0.title == "Refactor networking layer" }) {
            model.move(taskID: task.id, to: .inProgress, at: 0)
            model.setRunContext(.current, for: task.id)
            model.setPiSessionID(UUID(), for: task.id)
        }

        model.addTask(
            title: "Fix auth token refresh",
            prompt: "Auth tokens are not refreshed before expiry; add a refresh check before each request.",
            to: projectID
        )
        if let task = model.tasks(for: projectID, status: .backlog).first(where: { $0.title == "Fix auth token refresh" }) {
            model.move(taskID: task.id, to: .inProgress, at: 1)
            model.setRunContext(.worktree, for: task.id)
        }

        let doneTitles = [
            ("Set up CI pipeline", "Configure CI to run build and tests on every push."),
            ("Migrate to Swift 6 concurrency", "Adopt strict concurrency checking across the codebase."),
            ("Add project icon", "Design and add an app icon."),
        ]
        for (index, pair) in doneTitles.enumerated() {
            model.addTask(title: pair.0, prompt: pair.1, to: projectID)
            if let task = model.tasks(for: projectID, status: .backlog).first(where: { $0.title == pair.0 }) {
                model.move(taskID: task.id, to: .done, at: index)
                if index == 0 {
                    model.setRunContext(.current, for: task.id)
                    model.setPiSessionID(UUID(), for: task.id)
                }
            }
        }
    }

    private static func seedWebsiteTasks(into model: BoardModel, projectID: UUID) {
        model.addTask(
            title: "Update landing page hero",
            prompt: "Replace the hero image and update the copy for the new release.",
            to: projectID
        )

        model.addTask(
            title: "Fix mobile nav overflow",
            prompt: "The mobile nav menu overflows on small screens.",
            to: projectID
        )
        if let task = model.tasks(for: projectID, status: .backlog).first(where: { $0.title == "Fix mobile nav overflow" }) {
            model.move(taskID: task.id, to: .inProgress, at: 0)
            model.setRunContext(.current, for: task.id)
        }
    }
}
