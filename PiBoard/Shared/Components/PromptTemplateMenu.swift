import SwiftUI

/// "Insert Template" menu shared by the New Task sheet and the preparation sheet. Hidden when
/// the user has no templates, so the sheets look as before.
struct PromptTemplateMenu: View {
    static let title = "Insert Template"
    private static let systemImage = "text.badge.plus"

    @Binding var prompt: String
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let templates = environment.preferences.promptTemplates
        if !templates.isEmpty {
            Menu {
                ForEach(templates) { template in
                    Button(template.name) { prompt = PromptTemplate.insert(template, into: prompt) }
                }
            } label: {
                Label(Self.title, systemImage: Self.systemImage)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .accessibilityIdentifier(AccessibilityID.insertTemplate)
        }
    }
}
