import OSLog

enum Diagnostics {
    static let subsystem = "dev.piboard"

    // Presentation and terminal attach/detach events, so a frozen window can be diagnosed
    // from `log show` without a sampler.
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
