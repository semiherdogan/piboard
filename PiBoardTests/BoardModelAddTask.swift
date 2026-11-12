import Foundation
@testable import PiBoard

extension BoardModel {
    /// Most tests do not care about the agent; the app code always passes one explicitly.
    @discardableResult
    func addTask(title: String, prompt: String, to project: UUID) -> BoardTask.ID? {
        addTask(title: title, prompt: prompt, to: project, agent: .default)
    }

    func addTaskToPrepare(title: String, prompt: String, to project: UUID) {
        addTaskToPrepare(title: title, prompt: prompt, to: project, agent: .default)
    }
}
