import SwiftUI
import UniformTypeIdentifiers

private enum BoardColumnDropAnimation {
    static let highlight = Animation.easeOut(duration: 0.12)
}

@MainActor
private struct ColumnDropDelegate: DropDelegate {
    let status: TaskStatus
    let board: BoardModel
    let isRunning: (UUID) -> Bool
    let cardFrames: () -> [UUID: CGRect]
    let tasksInColumn: () -> [BoardTask]
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        board.draggingTaskID != nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        withAnimation(BoardColumnDropAnimation.highlight) {
            isTargeted = true
        }
    }

    func dropExited(info: DropInfo) {
        withAnimation(BoardColumnDropAnimation.highlight) {
            isTargeted = false
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let taskID = board.draggingTaskID else { return false }
        let frames = cardFrames()
        let columnTasks = tasksInColumn()
        let location = info.location
        let index = columnTasks.firstIndex { task in
            guard let frame = frames[task.id] else { return false }
            return frame.midY > location.y
        } ?? columnTasks.count
        withAnimation(.snappy) {
            board.requestMove(taskID: taskID, to: status, at: index, isRunning: isRunning)
        }
        board.draggingTaskID = nil
        return true
    }
}

struct BoardColumnView: View {
    let project: Project
    let status: TaskStatus
    @Environment(AppEnvironment.self) private var environment
    @State private var cardFrames: [UUID: CGRect] = [:]
    @State private var isTargeted = false

    private var tasks: [BoardTask] {
        environment.board.tasks(for: project.id, status: status)
    }

    private var emptyStateText: String {
        switch status {
        case .backlog: "Nothing in Backlog"
        case .inProgress: "Drag a task here to start it"
        case .done: "Nothing finished yet"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            ScrollView(.vertical) {
                VStack(spacing: 8) {
                    ForEach(tasks) { task in
                        TaskCardView(task: task)
                            .onGeometryChange(for: CGRect.self) { proxy in
                                proxy.frame(in: .named(columnCoordinateSpace))
                            } action: { frame in
                                cardFrames[task.id] = frame
                            }
                    }

                    if tasks.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .top)
            }
            .coordinateSpace(name: columnCoordinateSpace)
            .onDrop(of: [.text], delegate: ColumnDropDelegate(
                status: status,
                board: environment.board,
                isRunning: isTaskRunning,
                cardFrames: { cardFrames },
                tasksInColumn: { tasks },
                isTargeted: $isTargeted
            ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(isTargeted ? 1 : 0)
        )
    }

    private func isTaskRunning(_ taskID: UUID) -> Bool {
        let state = environment.processes.runtimeState(for: taskID)
        return state == .running || state == .starting
    }

    private var columnCoordinateSpace: String {
        "board-column-\(status.rawValue)"
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(status.title)
                .font(.headline)
            Text("\(tasks.count)")
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
