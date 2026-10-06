// Task-level runtime state per spec section 10.2; distinct from PTYRuntimeState, which tracks
// the process level of a single PTY session.
enum TaskRuntimeState: Equatable, Sendable {
    case notStarted
    case starting
    case running
    case stopping
    case exited(Int32?)
    case failed(String)

    var isActive: Bool {
        switch self {
        case .starting, .running, .stopping: true
        case .notStarted, .exited, .failed: false
        }
    }

    var label: String {
        switch self {
        case .notStarted: "Not Started"
        case .starting: "Starting"
        case .running: "Running"
        case .stopping: "Stopping"
        case .exited(let code):
            if let code, code != 0 {
                "Exited (\(code))"
            } else {
                "Finished"
            }
        case .failed: "Failed"
        }
    }

    var systemImage: String {
        switch self {
        case .notStarted: "circle"
        case .starting: "circle.dotted"
        case .running: "play.circle.fill"
        case .stopping: "stop.circle"
        case .exited(let code):
            (code ?? 0) == 0 ? "checkmark.circle" : "xmark.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}
