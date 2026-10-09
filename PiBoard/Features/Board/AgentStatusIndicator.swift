import SwiftUI

/// Says what is going on with a task, or with a project's tasks taken together. Several kinds can
/// show at once: one agent can still be working while another has already finished.
struct AgentStatusIndicator: View {
    enum Kind {
        /// An agent is starting or running right now.
        case working
        /// A Pi is alive but waiting at the prompt.
        case idle
        /// An agent finished while the user was looking elsewhere.
        case finished

        var label: String {
            switch self {
            case .working: "Agent working"
            case .idle: "Agent idle"
            case .finished: "Agent finished"
            }
        }

        fileprivate var color: AnyShapeStyle {
            switch self {
            case .working: AgentStatusIndicator.workingColor
            case .idle: AgentStatusIndicator.idleColor
            case .finished: AgentStatusIndicator.finishedColor
            }
        }
    }

    private static let workingColor = AnyShapeStyle(.green)
    private static let idleColor = AnyShapeStyle(Color.secondary)
    private static let finishedColor = AnyShapeStyle(.tint)
    private static let pulseMinimumOpacity = 0.35
    private static let pulseDuration = 0.9

    let kind: Kind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false
    @ScaledMetric(relativeTo: .caption) private var dotDiameter: CGFloat = 7
    @ScaledMetric(relativeTo: .caption) private var slotWidth: CGFloat = 14

    var body: some View {
        Circle()
            .fill(kind.color)
            .frame(width: dotDiameter, height: dotDiameter)
            .opacity(isPulsing ? Self.pulseMinimumOpacity : 1)
            .animation(pulseAnimation, value: isPulsing)
            .onAppear { isPulsing = pulses }
            // A fixed slot keeps neighbouring text from shifting as dots come and go.
            .frame(width: slotWidth)
            .accessibilityLabel(kind.label)
            .help(kind.label)
    }

    private var pulses: Bool {
        kind == .working && !reduceMotion
    }

    private var pulseAnimation: Animation? {
        pulses ? .easeInOut(duration: Self.pulseDuration).repeatForever(autoreverses: true) : nil
    }
}
