import Foundation

enum PromptComposer {
    static func compose(prompt: String, planFirst: Bool, suffix: String) -> String {
        guard planFirst else { return prompt }
        let trimmedSuffix = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSuffix.isEmpty else { return prompt }

        let trimmedPrompt = prompt.trimmingTrailingWhitespace()
        guard !trimmedPrompt.isEmpty else { return trimmedSuffix }
        return trimmedPrompt + "\n\n" + trimmedSuffix
    }
}

private extension String {
    func trimmingTrailingWhitespace() -> String {
        var result = Substring(self)
        while let last = result.last, last.isWhitespace || last.isNewline {
            result = result.dropLast()
        }
        return String(result)
    }
}
