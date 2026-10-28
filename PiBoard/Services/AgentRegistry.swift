import Foundation

/// Adapters by kind. A kind without an adapter is a programming error, so lookup is non-optional.
@MainActor
struct AgentRegistry {
    private let adapters: [AgentKind: any AgentAdapter]

    init(_ adapters: [any AgentAdapter]) {
        self.adapters = Dictionary(uniqueKeysWithValues: adapters.map { ($0.kind, $0) })
    }

    func adapter(for kind: AgentKind) -> any AgentAdapter {
        guard let adapter = adapters[kind] else {
            preconditionFailure("No agent adapter registered for \(kind.rawValue)")
        }
        return adapter
    }

    func adapter(for task: BoardTask) -> any AgentAdapter {
        adapter(for: task.agent)
    }
}
