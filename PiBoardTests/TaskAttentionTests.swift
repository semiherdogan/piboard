import Foundation
import Testing
@testable import PiBoard

@MainActor
struct TaskAttentionTests {
    private let first = UUID()
    private let second = UUID()

    @Test func marksAndClearsOneTaskAtATime() {
        let attention = TaskAttention()
        attention.mark(taskID: first)
        attention.mark(taskID: second)
        #expect(attention.has(taskID: first))

        attention.clear(taskID: first)
        #expect(!attention.has(taskID: first))
        #expect(attention.has(taskID: second))
    }

    @Test func markingTwiceLeavesOneMark() {
        let attention = TaskAttention()
        attention.mark(taskID: first)
        attention.mark(taskID: first)
        attention.clear(taskID: first)
        #expect(!attention.has(taskID: first))
    }

    // The project row has no task of its own, so it asks about all the tasks it contains.
    @Test func aProjectIsMarkedWhenAnyOfItsTasksIs() {
        let attention = TaskAttention()
        #expect(!attention.hasAny(of: [first, second]))

        attention.mark(taskID: second)
        #expect(attention.hasAny(of: [first, second]))
        #expect(!attention.hasAny(of: [first]))
    }

    @Test func clearingAnUnmarkedTaskIsHarmless() {
        let attention = TaskAttention()
        attention.clear(taskID: first)
        #expect(attention.taskIDs.isEmpty)
    }
}
