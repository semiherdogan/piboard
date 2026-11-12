import SwiftUI

/// First row of every agent tab. The last enabled agent stays on; `AppPreferences` would undo turning it off anyway.
struct AgentEnabledToggle: View {
    static let title = "Enabled"
    static let caption = "Offered in the task preparation and project sheets. Off greys it out there; existing tasks keep their agent."
    static let lastAgentCaption = "At least one agent stays enabled."

    let kind: AgentKind
    @Environment(AppEnvironment.self) private var environment

    private var isLastEnabled: Bool {
        let enabled = environment.preferences.enabledAgents
        return enabled.count == 1 && enabled.contains(kind)
    }

    @ViewBuilder
    var body: some View {
        Toggle(Self.title, isOn: binding)
            .disabled(isLastEnabled)
            .accessibilityIdentifier(AccessibilityID.agentToggle(kind))
        Text(isLastEnabled ? Self.lastAgentCaption : Self.caption)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var binding: Binding<Bool> {
        let preferences = environment.preferences
        return Binding(
            get: { preferences.enabledAgents.contains(kind) },
            set: { isOn in
                if isOn {
                    preferences.enabledAgents.insert(kind)
                } else {
                    preferences.enabledAgents.remove(kind)
                }
            }
        )
    }
}
