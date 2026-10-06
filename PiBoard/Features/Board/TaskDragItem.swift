import CoreTransferable
import Foundation

// Carries a BoardTask.ID as a plain string so drag and drop doesn't need a custom UTType.
struct TaskDragItem: Transferable {
    let taskID: UUID

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(
            exporting: { $0.taskID.uuidString },
            importing: { TaskDragItem(taskID: UUID(uuidString: $0) ?? UUID()) }
        )
    }
}
