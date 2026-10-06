import Foundation
import Testing
@testable import PiBoard

@MainActor
struct BoardDragControllerTests {
    private let cardFrame = CGRect(x: 20, y: 100, width: 200, height: 60)

    @Test func beginSetsGrabOffsetAndCardSizeFromFrame() {
        let controller = BoardDragController()
        let taskID = UUID()

        controller.begin(taskID: taskID, location: CGPoint(x: 50, y: 110), cardFrame: cardFrame)

        #expect(controller.draggingTaskID == taskID)
        #expect(controller.grabOffset == CGSize(width: 30, height: 10))
        #expect(controller.cardSize == cardFrame.size)
        #expect(controller.dragLocation == CGPoint(x: 50, y: 110))
    }

    @Test func endReturnsTaskAndLastTargetAndClearsState() throws {
        let controller = BoardDragController()
        let taskID = UUID()
        controller.columnFrames = [
            .backlog: CGRect(x: 0, y: 0, width: 200, height: 600),
            .done: CGRect(x: 216, y: 0, width: 200, height: 600)
        ]
        controller.begin(taskID: taskID, location: CGPoint(x: 50, y: 110), cardFrame: cardFrame)
        controller.update(location: CGPoint(x: 300, y: 50)) { _ in [] }

        let result = try #require(controller.end())

        #expect(result.0 == taskID)
        #expect(result.1 == DragTarget(status: .done, index: 0))
        #expect(controller.draggingTaskID == nil)
        #expect(controller.target == nil)
        #expect(controller.cardSize == .zero)
    }

    @Test func endWithoutTargetReturnsNil() {
        let controller = BoardDragController()
        controller.begin(taskID: UUID(), location: .zero, cardFrame: cardFrame)

        #expect(controller.end() == nil)
        #expect(controller.draggingTaskID == nil)
    }

    @Test func cancelClearsState() {
        let controller = BoardDragController()
        controller.columnFrames = [.backlog: CGRect(x: 0, y: 0, width: 200, height: 600)]
        controller.begin(taskID: UUID(), location: CGPoint(x: 50, y: 110), cardFrame: cardFrame)
        controller.update(location: CGPoint(x: 60, y: 120)) { _ in [] }

        controller.cancel()

        #expect(controller.draggingTaskID == nil)
        #expect(controller.target == nil)
        #expect(controller.grabOffset == .zero)
        #expect(controller.cardSize == .zero)
    }
}
