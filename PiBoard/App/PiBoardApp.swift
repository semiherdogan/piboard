import SwiftUI

@main
struct PiBoardApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environment(environment)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1280, height: 800)

        Settings {
            SettingsView()
                .environment(environment)
        }
    }
}
