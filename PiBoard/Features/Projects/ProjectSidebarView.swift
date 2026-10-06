import SwiftUI

struct ProjectSidebarView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showsNewProjectSheet = false

    private var board: BoardModel {
        environment.board
    }

    var body: some View {
        @Bindable var board = board

        Group {
            if board.projects.isEmpty {
                ContentUnavailableView {
                    Label("No Projects", systemImage: "folder")
                } description: {
                    Text("Add a project folder to get started.")
                } actions: {
                    Button("Add Project") {
                        showsNewProjectSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List(selection: $board.selectedProjectID) {
                    Section("Projects") {
                        ForEach(board.projects) { project in
                            projectRow(project)
                                .tag(project.id)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle("Projects")
        .safeAreaInset(edge: .bottom) {
            footer
        }
        .sheet(isPresented: $showsNewProjectSheet) {
            NewProjectSheet()
        }
    }

    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                Text(abbreviatedPath(project.path))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func abbreviatedPath(_ path: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let rawPath = path.path
        if rawPath.hasPrefix(home) {
            return "~" + rawPath.dropFirst(home.count)
        }
        return rawPath
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Divider()
            HStack {
                Button(action: { showsNewProjectSheet = true }) {
                    Label("New Project", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                Spacer()
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
