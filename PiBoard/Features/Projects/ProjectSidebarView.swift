import SwiftUI

struct ProjectSidebarView: View {
    var body: some View {
        List {
            Section("Projects") {
                ContentUnavailableView(
                    "No Projects",
                    systemImage: "folder",
                    description: Text("Add a project folder to get started.")
                )
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Projects")
    }
}
