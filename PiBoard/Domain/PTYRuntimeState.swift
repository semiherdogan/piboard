enum PTYRuntimeState: Equatable, Sendable {
    case notStarted
    case running
    case exited(Int32?)
}
