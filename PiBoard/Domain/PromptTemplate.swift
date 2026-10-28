import Foundation

/// A reusable prompt the user picks from a menu in the task sheets.
struct PromptTemplate: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var text: String

    static let defaultName = "New Template"

    init(id: UUID = UUID(), name: String = defaultName, text: String = "") {
        self.id = id
        self.name = name
        self.text = text
    }

    /// Appends the template to what is already typed, on its own paragraph.
    static func insert(_ template: PromptTemplate, into prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? template.text : trimmed + "\n\n" + template.text
    }
}
