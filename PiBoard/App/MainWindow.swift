import SwiftUI

struct MainWindow: View {
    // Temporary spike UI (M0 step 2); delete alongside TerminalSpikeView once the real
    // terminal integration replaces it.
    @State private var showsTerminalSpike = false

    var body: some View {
        NavigationSplitView {
            ProjectSidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            if showsTerminalSpike {
                TerminalSpikeView()
            } else {
                BoardView()
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Terminal Spike", systemImage: "terminal") {
                    showsTerminalSpike.toggle()
                }
            }
        }
    }
}
