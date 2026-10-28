import SwiftUI

struct RuntimeStatusBadge: View {
    let status: AgentRuntimeStatus

    var body: some View {
        switch status {
        case .unknown:
            Label("Unknown", systemImage: "questionmark.circle")
        case .missing:
            Label("Not installed", systemImage: "xmark.circle")
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill")
        }
    }
}
