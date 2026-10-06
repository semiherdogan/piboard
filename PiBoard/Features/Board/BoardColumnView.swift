import SwiftUI

enum DropIndexing {
    /// Finds where a dragged card should land among `orderedTaskIDs`, which still
    /// contains the dragged task; `excluding` removes it before comparing frames so the
    /// dragged card's own (stale) position doesn't shift the count.
    static func insertionIndex(
        location: CGPoint,
        orderedTaskIDs: [UUID],
        frames: [UUID: CGRect],
        excluding: UUID
    ) -> Int {
        let columnTaskIDs = orderedTaskIDs.filter { $0 != excluding }
        return columnTaskIDs.firstIndex { taskID in
            guard let frame = frames[taskID] else { return false }
            return frame.midY > location.y
        } ?? columnTaskIDs.count
    }
}

struct BoardColumnEntry: Identifiable {
    let task: BoardTask
    let role: TaskCardRole

    var id: UUID { task.id }
}

struct BoardColumnView: View {
    let status: TaskStatus
    let entries: [BoardColumnEntry]
    @Environment(BoardDragController.self) private var drag

    private var emptyStateText: String {
        switch status {
        case .backlog: "Nothing in Backlog"
        case .inProgress: "Drag a task here to start it"
        case .done: "Nothing finished yet"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header(count: entries.count)

            ScrollView(.vertical) {
                VStack(spacing: 8) {
                    ForEach(entries) { entry in
                        TaskCardView(task: entry.task, role: entry.role)
                            .onGeometryChange(for: CGRect.self) { proxy in
                                proxy.frame(in: .named(BoardCoordinateSpace.name))
                            } action: { frame in
                                drag.cardFrames[entry.id] = frame
                            }
                    }

                    if entries.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                }
                .animation(.snappy, value: entries.map(\.id))
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func header(count: Int) -> some View {
        HStack(spacing: 8) {
            Text(status.title)
                .font(.headline)
            Text("\(count)")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.title3)
            Text(emptyStateText)
                .font(.callout)
        }
        .foregroundStyle(.tertiary)
    }
}
