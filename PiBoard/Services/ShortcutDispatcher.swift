import AppKit

/// Routes recorded shortcuts while PiBoard is the active app. A local monitor needs no system
/// permission and runs before the key reaches the terminal, so Pi never sees a bound chord.
@MainActor
final class ShortcutDispatcher {
    /// Set while Settings is recording; the monitor must let those keys through to the recorder.
    var isRecording = false
    private var monitor: Any?
    private let preferences: AppPreferences
    var perform: (@MainActor (ShortcutAction) -> Void)?

    init(preferences: AppPreferences) {
        self.preferences = preferences
    }

    /// Local monitors are invoked on the main thread, so assuming isolation is safe.
    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            nonisolated(unsafe) let unsafeEvent = event
            let consumed = MainActor.assumeIsolated { self?.handle(unsafeEvent) ?? false }
            return consumed ? nil : event
        }
    }

    /// Must be called before release: a nonisolated deinit cannot touch the main-actor monitor.
    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        guard !isRecording, !event.isARepeat else { return false }
        for (action, shortcut) in preferences.keyboardShortcuts where shortcut.matches(event) {
            guard let perform else { return false }
            perform(action)
            return true
        }
        return false
    }
}
