import Observation
import SwiftUI

enum BoardCoordinateSpace {
    static let name = "board"
}

enum DragAppearance {
    static let minimumDragDistance: CGFloat = 4
    static let ghostScale: CGFloat = 1.03
    static let ghostShadowOpacity: Double = 0.2
    static let ghostShadowRadius: CGFloat = 12
    static let ghostShadowYOffset: CGFloat = 6
    static let ghostFade = Animation.easeOut(duration: 0.12)
    static let placeholderCornerRadius: CGFloat = 10
    static let placeholderDash: [CGFloat] = [4, 4]
    static let placeholderLineWidth: CGFloat = 1
}

struct DragTarget: Equatable {
    let status: TaskStatus
    let index: Int
}

@MainActor
@Observable
final class BoardDragController {
    private(set) var draggingTaskID: UUID?
    private(set) var dragLocation: CGPoint = .zero
    private(set) var grabOffset: CGSize = .zero
    private(set) var cardSize: CGSize = .zero
    private(set) var target: DragTarget?
    // Written from layout callbacks; ignored so those writes never invalidate a body.
    @ObservationIgnored var columnFrames: [TaskStatus: CGRect] = [:]
    @ObservationIgnored var cardFrames: [UUID: CGRect] = [:]

    func begin(taskID: UUID, location: CGPoint, cardFrame: CGRect) {
        draggingTaskID = taskID
        dragLocation = location
        grabOffset = CGSize(width: location.x - cardFrame.minX, height: location.y - cardFrame.minY)
        cardSize = cardFrame.size
        target = nil
    }

    func update(location: CGPoint, orderedIDs: (TaskStatus) -> [UUID]) {
        guard let draggingTaskID else { return }
        dragLocation = location
        let newTarget = BoardDragTargeting.target(
            location: location,
            columnFrames: columnFrames,
            orderedTaskIDs: orderedIDs,
            cardFrames: cardFrames,
            excluding: draggingTaskID
        )
        // Observation notifies on every assignment; the board body only needs to rerun on a real change.
        if newTarget != target {
            target = newTarget
        }
    }

    func end() -> (UUID, DragTarget)? {
        defer { cancel() }
        guard let draggingTaskID, let target else { return nil }
        return (draggingTaskID, target)
    }

    func cancel() {
        draggingTaskID = nil
        target = nil
        dragLocation = .zero
        grabOffset = .zero
        cardSize = .zero
    }
}
