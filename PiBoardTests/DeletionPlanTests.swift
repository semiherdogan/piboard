import Foundation
import Testing
@testable import PiBoard

struct DeletionPlanTests {
    private let projectID = UUID()
    private let taskIDs = [UUID(), UUID(), UUID()]

    private func worktree(_ taskID: UUID) -> PlannedWorktreeRemoval {
        PlannedWorktreeRemoval(
            taskID: taskID,
            info: WorktreeInfo(path: URL(fileURLWithPath: "/tmp/wt/\(taskID)"), branch: "piboard/task"),
            repository: URL(fileURLWithPath: "/tmp/repo")
        )
    }

    private func projectPlan(running: [UUID] = [], worktrees: [PlannedWorktreeRemoval] = []) -> DeletionPlan {
        DeletionPlan(
            subject: .project(id: projectID, name: "PiBoard"),
            taskIDs: taskIDs,
            runningTaskIDs: running,
            worktrees: worktrees
        )
    }

    private func taskPlan(running: Bool = false, worktrees: [PlannedWorktreeRemoval] = []) -> DeletionPlan {
        DeletionPlan(
            subject: .task(id: taskIDs[0], title: "Fix login"),
            taskIDs: [taskIDs[0]],
            runningTaskIDs: running ? [taskIDs[0]] : [],
            worktrees: worktrees
        )
    }

    @Test func titleNamesWhatIsBeingDeleted() {
        #expect(projectPlan().title == "Delete PiBoard?")
        #expect(taskPlan().title == "Delete Fix login?")
    }

    // The button has to say that agents get stopped, or the user cannot tell it from a plain delete.
    @Test func theConfirmButtonAnnouncesStoppingAgents() {
        #expect(projectPlan().confirmTitle == "Delete Project")
        #expect(projectPlan(running: [taskIDs[0]]).confirmTitle == "Stop Agents and Delete")
        #expect(taskPlan().confirmTitle == "Delete Task")
        #expect(taskPlan(running: true).confirmTitle == "Stop Agent and Delete")
    }

    @Test func aPlainProjectDeleteCountsItsTasks() {
        let message = projectPlan().message
        #expect(message.contains("3 tasks will be deleted."))
        #expect(message.contains("The project folder itself is not touched."))
        #expect(!message.contains("agent"))
        #expect(!message.contains("worktree"))
    }

    @Test func runningAgentsAreCountedAndPluralised() {
        #expect(projectPlan(running: [taskIDs[0]]).message.contains("1 agent is running and will be stopped."))
        #expect(projectPlan(running: Array(taskIDs.prefix(2))).message.contains("2 agents are running and will be stopped."))
    }

    // Losing uncommitted work is the only irreversible part, so it must be spelled out.
    @Test func worktreeRemovalWarnsAboutUncommittedChanges() {
        let single = projectPlan(worktrees: [worktree(taskIDs[0])]).message
        #expect(single.contains("1 worktree will be removed, along with any uncommitted changes in it."))

        let several = projectPlan(worktrees: taskIDs.prefix(2).map(worktree)).message
        #expect(several.contains("2 worktrees will be removed, along with any uncommitted changes in them."))
    }

    @Test func aTaskDeleteDoesNotCountTasks() {
        let message = taskPlan(running: true, worktrees: [worktree(taskIDs[0])]).message
        #expect(!message.contains("will be deleted."))
        #expect(message.contains("1 agent is running and will be stopped."))
        #expect(message.contains("1 worktree will be removed"))
        #expect(message.contains("Pi session files are not deleted."))
    }

    @Test func oneTaskProjectReadsAsSingular() {
        let plan = DeletionPlan(
            subject: .project(id: projectID, name: "Solo"),
            taskIDs: [taskIDs[0]],
            runningTaskIDs: [],
            worktrees: []
        )
        #expect(plan.message.contains("1 task will be deleted."))
    }
}
