enum PTYRuntimeState: Equatable, Sendable {
    case notStarted
    case running
    case exited(Int32?)

    var isRunning: Bool {
        self == .running
    }

    var exitCode: Int32? {
        if case .exited(let code) = self {
            return code
        }
        return nil
    }
}
