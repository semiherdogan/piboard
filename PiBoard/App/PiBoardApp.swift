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

        Settings {
            SettingsView()
                .environment(environment)
        }
    }
}
