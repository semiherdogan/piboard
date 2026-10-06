import Testing
@testable import PiBoard

struct TaskStatusTests {
    @Test func rawValuesMatchSchema() {
        #expect(TaskStatus.backlog.rawValue == "backlog")
        #expect(TaskStatus.inProgress.rawValue == "in_progress")
        #expect(TaskStatus.done.rawValue == "done")
    }

    @Test func columnOrderIsBacklogInProgressDone() {
        #expect(TaskStatus.allCases == [.backlog, .inProgress, .done])
    }
}
