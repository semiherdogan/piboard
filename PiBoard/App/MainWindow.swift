import SwiftUI

struct MainWindow: View {
    var body: some View {
        NavigationSplitView {
            ProjectSidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            BoardView()
        }
    }
}
