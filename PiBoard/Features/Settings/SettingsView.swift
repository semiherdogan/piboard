import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                Form {
                    Text("General preferences will appear here.")
                        .foregroundStyle(.secondary)
                }
                .formStyle(.grouped)
            }
            Tab("Pi Runtime", systemImage: "terminal") {
                PiRuntimeSettingsView()
            }
        }
        .frame(width: 520, height: 320)
    }
}
