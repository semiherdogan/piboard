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
        .defaultSize(width: 1200, height: 760)

        Settings {
            SettingsView()
                .environment(environment)
        }
    }
}
