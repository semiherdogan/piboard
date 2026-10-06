import Foundation

enum BoardDragTargeting {
    static func target(
        location: CGPoint,
        columnFrames: [TaskStatus: CGRect],
        orderedTaskIDs: (TaskStatus) -> [UUID],
        cardFrames: [UUID: CGRect],
        excluding: UUID
    ) -> DragTarget? {
        guard let status = column(atX: location.x, columnFrames: columnFrames) else { return nil }
        let index = DropIndexing.insertionIndex(
            location: location,
            orderedTaskIDs: orderedTaskIDs(status),
            frames: cardFrames,
            excluding: excluding
        )
        return DragTarget(status: status, index: index)
    }

    // Only x matters so dragging above or below a column still targets it; iterating
    // allCases keeps ties deterministic, unlike dictionary order.
    private static func column(atX x: CGFloat, columnFrames: [TaskStatus: CGRect]) -> TaskStatus? {
        var nearest: (status: TaskStatus, distance: CGFloat)?
        for status in TaskStatus.allCases {
            guard let frame = columnFrames[status] else { continue }
            if x >= frame.minX, x <= frame.maxX {
                return status
            }
            let distance = x < frame.minX ? frame.minX - x : x - frame.maxX
            if nearest.map({ distance < $0.distance }) ?? true {
                nearest = (status, distance)
            }
        }
        return nearest?.status
    }
}
