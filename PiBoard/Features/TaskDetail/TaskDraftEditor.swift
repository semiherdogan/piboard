import Foundation
import Observation

/// Holds the inspector's title and prompt while the user types and writes them back after a
/// pause, so a keystroke is not a SQLite UPDATE. `flush` writes a pending draft at once.
@MainActor
@Observable
final class TaskDraftEditor {
    static let defaultWriteDelay: Duration = .milliseconds(300)

    var title = "" {
        didSet { if title != oldValue { scheduleWrite() } }
    }
    var prompt = "" {
        didSet { if prompt != oldValue { scheduleWrite() } }
    }
    /// Exposed so tests can await the delayed write instead of sleeping.
    private(set) var writeTask: Task<Void, Never>?
    /// Set by the view, which knows the task the draft belongs to.
    @ObservationIgnored var onWrite: @MainActor (_ title: String, _ prompt: String) -> Void = { _, _ in }

    private let writeDelay: Duration
    private var writtenTitle = ""
    private var writtenPrompt = ""

    init(writeDelay: Duration = defaultWriteDelay) {
        self.writeDelay = writeDelay
    }

    var hasPendingChanges: Bool {
        title != writtenTitle || prompt != writtenPrompt
    }

    /// Replaces the draft with stored values. A write still pending for the previous values goes
    /// out first, so switching tasks never loses typing.
    func load(title: String, prompt: String) {
        flush()
        writtenTitle = title
        writtenPrompt = prompt
        self.title = title
        self.prompt = prompt
    }

    /// Writes now when something changed; cancels the delayed write either way.
    func flush() {
        writeTask?.cancel()
        writeTask = nil
        guard hasPendingChanges else { return }
        writtenTitle = title
        writtenPrompt = prompt
        onWrite(title, prompt)
    }

    private func scheduleWrite() {
        writeTask?.cancel()
        guard hasPendingChanges else {
            writeTask = nil
            return
        }
        writeTask = Task { [weak self, writeDelay] in
            try? await Task.sleep(for: writeDelay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }
}
