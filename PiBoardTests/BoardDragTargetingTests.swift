import Foundation
import Testing
@testable import PiBoard

struct BoardDragTargetingTests {
    private let columnFrames: [TaskStatus: CGRect] = [
        .backlog: CGRect(x: 0, y: 0, width: 200, height: 600),
        .inProgress: CGRect(x: 216, y: 0, width: 200, height: 600),
        .done: CGRect(x: 432, y: 0, width: 200, height: 600)
    ]

    private func target(at location: CGPoint, ids: [UUID] = [], frames: [UUID: CGRect] = [:], excluding: UUID = UUID()) -> DragTarget? {
        BoardDragTargeting.target(
            location: location,
            columnFrames: columnFrames,
            orderedTaskIDs: { _ in ids },
            cardFrames: frames,
            excluding: excluding
        )
    }

    private func stackedFrames(_ ids: [UUID]) -> [UUID: CGRect] {
        Dictionary(uniqueKeysWithValues: ids.enumerated().map { offset, id in
            (id, CGRect(x: 216, y: 48 * CGFloat(offset), width: 200, height: 40))
        })
    }

    @Test func locationInsideColumnPicksThatColumn() {
        #expect(target(at: CGPoint(x: 300, y: 100))?.status == .inProgress)
    }

    @Test func locationAboveColumnStillPicksItByX() {
        #expect(target(at: CGPoint(x: 300, y: -50))?.status == .inProgress)
    }

    @Test func locationLeftOfAllColumnsPicksLeftmost() {
        #expect(target(at: CGPoint(x: -80, y: 100))?.status == .backlog)
    }

    @Test func locationRightOfAllColumnsPicksRightmost() {
        #expect(target(at: CGPoint(x: 900, y: 100))?.status == .done)
    }

    @Test func noColumnFramesYieldsNil() {
        let result = BoardDragTargeting.target(
            location: .zero,
            columnFrames: [:],
            orderedTaskIDs: { _ in [] },
            cardFrames: [:],
            excluding: UUID()
        )
        #expect(result == nil)
    }

    @Test func indexAboveFirstCardIsZero() {
        let ids = [UUID(), UUID(), UUID()]
        #expect(target(at: CGPoint(x: 300, y: 5), ids: ids, frames: stackedFrames(ids))?.index == 0)
    }

    @Test func indexBetweenFirstAndSecondCardIsOne() {
        let ids = [UUID(), UUID(), UUID()]
        #expect(target(at: CGPoint(x: 300, y: 44), ids: ids, frames: stackedFrames(ids))?.index == 1)
    }

    @Test func indexBelowAllCardsIsCount() {
        let ids = [UUID(), UUID(), UUID()]
        #expect(target(at: CGPoint(x: 300, y: 500), ids: ids, frames: stackedFrames(ids))?.index == ids.count)
    }

    @Test func excludedTaskIsIgnored() {
        let ids = [UUID(), UUID(), UUID()]
        // The dragged middle card sits above the pointer; counting it would shift the index to 2.
        let result = target(at: CGPoint(x: 300, y: 80), ids: ids, frames: stackedFrames(ids), excluding: ids[1])
        #expect(result == DragTarget(status: .inProgress, index: 1))
        let unexcluded = target(at: CGPoint(x: 300, y: 80), ids: ids, frames: stackedFrames(ids))
        #expect(unexcluded?.index == 2)
    }
}
