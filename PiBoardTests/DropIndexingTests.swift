import Foundation
import Testing
@testable import PiBoard

struct DropIndexingTests {
    @Test func locationAboveFirstCardYieldsZero() {
        let (first, second, third) = (UUID(), UUID(), UUID())
        let frames: [UUID: CGRect] = [
            first: CGRect(x: 0, y: 0, width: 200, height: 40),
            second: CGRect(x: 0, y: 48, width: 200, height: 40),
            third: CGRect(x: 0, y: 96, width: 200, height: 40)
        ]

        let index = DropIndexing.insertionIndex(
            location: CGPoint(x: 100, y: -10),
            orderedTaskIDs: [first, second, third],
            frames: frames,
            excluding: UUID()
        )

        #expect(index == 0)
    }

    @Test func locationBetweenFirstAndSecondCardYieldsOne() {
        let (first, second, third) = (UUID(), UUID(), UUID())
        let frames: [UUID: CGRect] = [
            first: CGRect(x: 0, y: 0, width: 200, height: 40),
            second: CGRect(x: 0, y: 48, width: 200, height: 40),
            third: CGRect(x: 0, y: 96, width: 200, height: 40)
        ]

        let index = DropIndexing.insertionIndex(
            location: CGPoint(x: 100, y: 44),
            orderedTaskIDs: [first, second, third],
            frames: frames,
            excluding: UUID()
        )

        #expect(index == 1)
    }

    @Test func locationBelowAllCardsYieldsCount() {
        let (first, second, third) = (UUID(), UUID(), UUID())
        let frames: [UUID: CGRect] = [
            first: CGRect(x: 0, y: 0, width: 200, height: 40),
            second: CGRect(x: 0, y: 48, width: 200, height: 40),
            third: CGRect(x: 0, y: 96, width: 200, height: 40)
        ]

        let index = DropIndexing.insertionIndex(
            location: CGPoint(x: 100, y: 200),
            orderedTaskIDs: [first, second, third],
            frames: frames,
            excluding: UUID()
        )

        #expect(index == 3)
    }

    @Test func excludedTaskIsRemovedBeforeComparingFrames() {
        // Dragging `second` downward to just above `third`: once `second` is excluded,
        // `third` becomes the only card below the drop point, so the target index is 1.
        let (first, second, third) = (UUID(), UUID(), UUID())
        let frames: [UUID: CGRect] = [
            first: CGRect(x: 0, y: 0, width: 200, height: 40),
            second: CGRect(x: 0, y: 48, width: 200, height: 40),
            third: CGRect(x: 0, y: 96, width: 200, height: 40)
        ]

        let index = DropIndexing.insertionIndex(
            location: CGPoint(x: 100, y: 110),
            orderedTaskIDs: [first, second, third],
            frames: frames,
            excluding: second
        )

        #expect(index == 1)
    }
}
