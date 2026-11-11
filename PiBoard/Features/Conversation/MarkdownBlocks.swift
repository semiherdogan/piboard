import Foundation

/// Splits assistant text into paragraphs and fenced code blocks; everything inline is left to `AttributedString(markdown:)`.
enum MarkdownBlocks {
    enum Block: Equatable {
        case paragraph(String)
        case code(language: String?, text: String)
    }

    private static let fence = "```"
    private static let lineSeparator: Character = "\n"

    static func split(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [Substring] = []
        var code: [Substring] = []
        var language: String?
        var isInFence = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: String(lineSeparator))))
            paragraph.removeAll()
        }

        for line in text.split(separator: lineSeparator, omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isInFence {
                if trimmed == fence {
                    blocks.append(.code(language: language, text: code.joined(separator: String(lineSeparator))))
                    code.removeAll()
                    isInFence = false
                } else {
                    code.append(line)
                }
            } else if trimmed.hasPrefix(fence) {
                flushParagraph()
                let tag = trimmed.dropFirst(fence.count).trimmingCharacters(in: .whitespaces)
                language = tag.isEmpty ? nil : tag
                isInFence = true
            } else if trimmed.isEmpty {
                flushParagraph()
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        // A fence still open means the text is streaming: show what arrived so far.
        if isInFence {
            blocks.append(.code(language: language, text: code.joined(separator: String(lineSeparator))))
        }
        return blocks
    }
}
