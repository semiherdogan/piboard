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
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    environment.updates.checkForUpdates()
                }
                .disabled(!environment.updates.canCheckForUpdates)
            }
        }

        Settings {
            SettingsView()
                .environment(environment)
        }
    }
}
