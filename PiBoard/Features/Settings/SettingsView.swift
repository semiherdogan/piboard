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
                Form {
                    Text("Pi runtime status, install, update and rollback will appear here.")
                        .foregroundStyle(.secondary)
                }
                .formStyle(.grouped)
            }
        }
        .frame(width: 520, height: 320)
    }
}
