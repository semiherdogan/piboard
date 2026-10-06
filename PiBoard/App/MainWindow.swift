import SwiftUI

struct MainWindow: View {
    // Temporary spike UI (M0 step 2); delete alongside TerminalSpikeView once the real
    // terminal integration replaces it.
    @State private var showsTerminalSpike = false
    @State private var showsInspector = false
    @Environment(AppEnvironment.self) private var environment

    private var selectedProject: Project? {
        environment.board.projects.first { $0.id == environment.board.selectedProjectID }
    }

    var body: some View {
        NavigationSplitView {
            ProjectSidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            if showsTerminalSpike {
                TerminalSpikeView()
            } else if let selectedProject {
                BoardView(project: selectedProject)
                    .inspector(isPresented: $showsInspector) {
                        if let taskID = environment.board.selectedTaskID {
                            TaskInspectorView(taskID: taskID)
                                .inspectorColumnWidth(ideal: 300)
                        } else {
                            ContentUnavailableView("No Task Selected", systemImage: "square.text.square")
                                .inspectorColumnWidth(ideal: 300)
                        }
                    }
            } else {
                ContentUnavailableView("Select a Project", systemImage: "sidebar.left")
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Terminal Spike", systemImage: "terminal") {
                    showsTerminalSpike.toggle()
                }
            }
            ToolbarItem {
                Button("Inspector", systemImage: "sidebar.right") {
                    showsInspector.toggle()
                }
            }
        }
        .frame(minWidth: 960, minHeight: 640)
    }
}
