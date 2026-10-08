import AppKit
import SwiftUI

struct ShortcutsSettingsView: View {
    private static let sectionTitle = "Shortcuts"
    private static let footer = "Shortcuts work while PiBoard is the active app. Press Escape to cancel a recording."

    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases, id: \.self) { action in
                    LabeledContent(action.title) {
                        ShortcutRecorderButton(action: action)
                    }
                }
                Text(Self.footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(Self.sectionTitle)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutRecorderButton: View {
    private static let idleTitle = "Record Shortcut"
    private static let recordingTitle = "Press keys..."
    private static let clearIcon = "xmark.circle"
    private static let clearLabel = "Clear Shortcut"

    let action: ShortcutAction
    @Environment(AppEnvironment.self) private var environment
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        let current = environment.preferences.shortcut(for: action)
        HStack {
            Button(isRecording ? Self.recordingTitle : (current?.display ?? Self.idleTitle)) {
                isRecording ? stopRecording() : startRecording()
            }
            if current != nil {
                Button(Self.clearLabel, systemImage: Self.clearIcon) {
                    environment.preferences.setShortcut(nil, for: action)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        environment.shortcuts.isRecording = true
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            nonisolated(unsafe) let unsafeEvent = event
            MainActor.assumeIsolated { handle(unsafeEvent) }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
        environment.shortcuts.isRecording = false
    }

    /// Every key is swallowed while recording so nothing leaks into the focused control.
    private func handle(_ event: NSEvent) {
        if event.keyCode == KeyboardShortcut.escapeKeyCode {
            stopRecording()
        } else if let shortcut = KeyboardShortcut(event: event) {
            environment.preferences.setShortcut(shortcut, for: action)
            stopRecording()
        }
    }
}
