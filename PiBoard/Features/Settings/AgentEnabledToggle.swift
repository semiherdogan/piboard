import SwiftUI

/// First row of every agent tab. The default agent stays on; `AppPreferences` would re-insert it anyway.
struct AgentEnabledToggle: View {
    static let title = "Enabled"
    static let caption = "Offered in the task preparation and project sheets. Off greys it out there; existing tasks keep their agent."
    static let defaultCaption = "The default agent is always available."

    let kind: AgentKind
    @Environment(AppEnvironment.self) private var environment

    private var isDefault: Bool { kind == AgentKind.default }

    @ViewBuilder
    var body: some View {
        Toggle(Self.title, isOn: binding)
            .disabled(isDefault)
            .accessibilityIdentifier(AccessibilityID.agentToggle(kind))
        Text(isDefault ? Self.defaultCaption : Self.caption)
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
