import Foundation

/// Which Pi-compatible CLI runs a `.pi` task. Both share `~/.pi/agent`, so a task keeps its
/// session when the engine changes. Raw values are stored in SQLite; never rename one.
enum PiEngine: String, CaseIterable, Sendable {
    /// Pi's npm package run by the bundled Node, installed and versioned by PiBoard.
    case pi
    /// PiG (Pi in Go), a native port installed and updated by the user.
    case pig

    static let `default` = PiEngine.pi

    var title: String {
        switch self {
        case .pi: "Pi"
        case .pig: "PiG"
        }
    }
}
