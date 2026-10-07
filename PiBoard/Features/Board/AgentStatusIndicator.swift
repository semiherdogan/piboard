import SwiftUI

/// Says what is going on with a task, or with a project's tasks taken together. Both states can
/// show at once: one agent can still be working while another has already finished.
struct AgentStatusIndicator: View {
    enum Kind {
        /// An agent is starting or running right now.
        case running
        /// An agent finished while the user was looking elsewhere.
        case finished

        var label: String {
            switch self {
            case .running: "Agent running"
            case .finished: "Agent finished"
            }
        }
    }

    let kind: Kind
    @ScaledMetric(relativeTo: .caption) private var dotDiameter: CGFloat = 7
    @ScaledMetric(relativeTo: .caption) private var slotWidth: CGFloat = 14

    var body: some View {
        content
            // A fixed slot keeps the project name from shifting as the spinner replaces the dot.
            .frame(width: slotWidth)
            .accessibilityLabel(kind.label)
            .help(kind.label)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .running:
            // The system's indeterminate indicator: it animates itself and reads as "busy"
            // without inventing a custom rotation.
            ProgressView()
                .controlSize(.mini)
        case .finished:
            Circle()
                .fill(.tint)
                .frame(width: dotDiameter, height: dotDiameter)
        }
    }
}
