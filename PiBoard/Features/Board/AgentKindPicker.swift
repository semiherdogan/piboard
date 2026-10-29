import SwiftUI

enum AgentPickerStyle { static let segmentedLimit = 3 }

/// Segmented while there are few agents, a menu beyond `segmentedLimit`. The current value is
/// always listed, even when its agent was turned off, so a stored choice never renders blank.
struct AgentKindPicker: View {
    let title: String
    @Binding var selection: AgentKind
    let choices: [AgentKind]

    private var options: [AgentKind] {
        choices.contains(selection) ? choices : choices + [selection]
    }

    var body: some View {
        let options = options
        if options.count <= AgentPickerStyle.segmentedLimit {
            picker(options).pickerStyle(.segmented)
        } else {
            picker(options).pickerStyle(.menu)
        }
    }

    private func picker(_ options: [AgentKind]) -> some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.self) { Text($0.title).tag($0) }
        }
    }
}
