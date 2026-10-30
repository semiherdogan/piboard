import SwiftUI

/// Menu listing every agent. Agents turned off in Settings stay visible but greyed out, so the
/// user sees what exists; the binding refuses them in case the platform ignores `disabled`.
struct AgentKindPicker: View {
    static let offSuffix = " (off)"

    let title: String
    @Binding var selection: AgentKind
    let enabled: [AgentKind]

    private var guardedSelection: Binding<AgentKind> {
        Binding(
            get: { selection },
            set: { kind in
                guard isSelectable(kind) else { return }
                selection = kind
            }
        )
    }

    var body: some View {
        Picker(title, selection: guardedSelection) {
            ForEach(AgentKind.allCases, id: \.self) { kind in
                Text(isSelectable(kind) ? kind.title : kind.title + Self.offSuffix)
                    .tag(kind)
                    .disabled(!isSelectable(kind))
            }
        }
        .pickerStyle(.menu)
    }

    // The stored value stays selectable even when its agent was turned off, so a saved choice never renders blank.
    private func isSelectable(_ kind: AgentKind) -> Bool {
        enabled.contains(kind) || kind == selection
    }
}
