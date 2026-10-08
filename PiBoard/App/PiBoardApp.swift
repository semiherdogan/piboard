import SwiftUI

@main
struct PiBoardApp: App {
    @State private var environment = AppEnvironment()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environment(environment)
                .onAppear { appDelegate.environment = environment }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1280, height: 800)
        .commands {
            // Replaced rather than appended: the stock item shows a panel with no credits, and
            // the repository link can only be passed when the panel is opened by hand.
            CommandGroup(replacing: .appInfo) {
                Button("About PiBoard") {
                    AboutPanel.show()
                }
                Button("Check for Updates...") {
                    environment.updates.checkForUpdates()
                }
                .disabled(!environment.updates.canCheckForUpdates)
            }

            // A menu shortcut is consumed before the terminal's keyDown, so Pi never sees it.
            CommandGroup(after: .pasteboard) {
                Button(TerminalFind.menuTitle) {
                    environment.showTerminalFindBar()
                }
                .keyboardShortcut(TerminalFind.shortcutKey, modifiers: .command)
                .disabled(!environment.canShowTerminalFindBar)
            }
        }

        Settings {
            SettingsView()
                .environment(environment)
        }
    }
}
