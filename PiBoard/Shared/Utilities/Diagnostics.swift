import OSLog

enum Diagnostics {
    static let subsystem = "dev.piboard"

    // Presentation and terminal attach/detach events, logged at notice level because macOS does
    // not persist info-level messages, so a frozen window can still be explained after a quit.
    static let ui = Logger(subsystem: subsystem, category: "ui")

    // Preflight, worktree lifecycle and launch working directories.
    static let git = Logger(subsystem: subsystem, category: "git")

    // Pi runtime install, activation and retention cleanup.
    static let runtime = Logger(subsystem: subsystem, category: "runtime")

    // Pi child process bookkeeping: session lookup before resume and leftover processes.
    static let process = Logger(subsystem: subsystem, category: "process")
}
