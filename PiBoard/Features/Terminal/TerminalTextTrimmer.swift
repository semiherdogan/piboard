import Foundation

private let trailingWhitespaceCharacters = CharacterSet(charactersIn: " \t\u{00A0}")

/// Trims trailing whitespace from each line and surrounding blank lines from a terminal
/// selection, without touching leading indentation.
enum TerminalTextTrimmer {
    static func trim(_ text: String?) -> String {
        guard let text else { return "" }

        let lines = text.components(separatedBy: .newlines)
        let trimmedLines = lines.map { line -> String in
            var trimmed = Substring(line)
            while let last = trimmed.unicodeScalars.last, trailingWhitespaceCharacters.contains(last) {
                trimmed = trimmed.dropLast()
            }
            return String(trimmed)
        }

        guard let firstNonBlank = trimmedLines.firstIndex(where: { !$0.isEmpty }),
            let lastNonBlank = trimmedLines.lastIndex(where: { !$0.isEmpty })
        else {
            return ""
        }

        return trimmedLines[firstNonBlank...lastNonBlank].joined(separator: "\n")
    }
}
