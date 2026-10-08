import SwiftUI

struct BoardTerminalDrawer: View {
    static let title = "Terminal"
    static let hideHelp = "Hide (keeps the shell running)"
    static let closeHelp = "Close (ends the shell)"
    static let systemImage = "terminal"
    static let runningSystemImage = "terminal.fill"

    let project: Project
    @Environment(AppEnvironment.self) private var environment
    @State private var dragStartHeight: Double?

    private var session: PTYSession? {
        environment.shells.session(for: project.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            divider
            header
            if let session {
                TerminalHostView(taskID: project.id, session: session)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: environment.preferences.terminalDrawerHeight)
        .onAppear(perform: openShell)
        .onChange(of: project.id) { openShell() }
        .onChange(of: session?.state) { _, state in
            guard case .exited = state else { return }
            environment.shells.forget(projectID: project.id)
            environment.board.isTerminalDrawerPresented = false
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(Self.title, systemImage: Self.systemImage)
                .font(.caption)
            Text(ProjectPathService.abbreviated(project.path))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                environment.board.isTerminalDrawerPresented = false
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .help(Self.hideHelp)
            Button {
                environment.shells.close(projectID: project.id)
                environment.board.isTerminalDrawerPresented = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help(Self.closeHelp)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func openShell() {
        environment.shells.open(projectID: project.id, directory: project.path)
    }

    // Dragging up grows the drawer, so the delta is subtracted. The height is read at drag
    // start and written through the preference so it is already persisted when the drag ends.
    private var divider: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: TerminalDrawerHeight.dividerHeight)
            .frame(height: TerminalDrawerHeight.dividerHitHeight)
            .contentShape(Rectangle())
            .pointerStyle(.rowResize)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartHeight == nil {
                            dragStartHeight = environment.preferences.terminalDrawerHeight
                        }
                        let proposed = (dragStartHeight ?? TerminalDrawerHeight.defaultValue) - value.translation.height
                        environment.preferences.terminalDrawerHeight = proposed.clamped(to: TerminalDrawerHeight.minimum...TerminalDrawerHeight.maximum)
                    }
                    .onEnded { _ in dragStartHeight = nil }
            )
    }
}
