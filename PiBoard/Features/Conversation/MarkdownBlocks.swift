import Foundation

/// Splits assistant text into headings, lists, paragraphs and fenced code blocks; everything inline is left to `AttributedString(markdown:)`.
enum MarkdownBlocks {
    struct ListItem: Equatable {
        /// The number of an ordered item; nil for a bullet.
        let ordinal: Int?
        let text: String
    }

    enum Block: Equatable {
        case paragraph(String)
        case heading(level: Int, text: String)
        case list([ListItem])
        case code(language: String?, text: String)
    }

    static let headlineLevel = 1
    static let subheadlineLevel = 2
    private static let fence = "```"
    private static let lineSeparator: Character = "\n"
    private static let lazyContinuationSeparator: Character = " "
    private static let bulletPrefixes = ["- ", "* "]
    private static let orderedSuffix: Character = "."
    private static let headingMarker: Character = "#"
    private static let maxHeadingLevel = 3
    private static let markerGap: Character = " "

    static func split(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [Substring] = []
        var items: [ListItem] = []
        var code: [Substring] = []
        var language: String?
        var isInFence = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: String(lineSeparator))))
            paragraph.removeAll()
        }

        func flushList() {
            guard !items.isEmpty else { return }
            blocks.append(.list(items))
            items.removeAll()
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
                flushList()
                let tag = trimmed.dropFirst(fence.count).trimmingCharacters(in: .whitespaces)
                language = tag.isEmpty ? nil : tag
                isInFence = true
            } else if trimmed.isEmpty {
                flushParagraph()
                flushList()
            } else if let heading = heading(in: line) {
                flushParagraph()
                flushList()
                blocks.append(heading)
            } else if let item = listItem(in: line) {
                flushParagraph()
                items.append(item)
            } else if !items.isEmpty {
                // Indented lines (nested lists included) stay plain text of the item; an unindented line is a lazy continuation (CommonMark).
                let separator = line.first?.isWhitespace == true ? lineSeparator : lazyContinuationSeparator
                let last = items.removeLast()
                items.append(ListItem(ordinal: last.ordinal, text: last.text + String(separator) + line))
            } else {
                flushList()
                paragraph.append(line)
            }
        }
        flushParagraph()
        flushList()
        // A fence still open means the text is streaming: show what arrived so far.
        if isInFence {
            blocks.append(.code(language: language, text: code.joined(separator: String(lineSeparator))))
        }
        return blocks
    }

    private static func heading(in line: Substring) -> Block? {
        let hashes = line.prefix { $0 == headingMarker }
        guard (1...maxHeadingLevel).contains(hashes.count) else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.first == markerGap else { return nil }
        let title = rest.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return .heading(level: hashes.count, text: title)
    }

    private static func listItem(in line: Substring) -> ListItem? {
        for prefix in bulletPrefixes where line.hasPrefix(prefix) {
            return ListItem(ordinal: nil, text: String(line.dropFirst(prefix.count)))
        }
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, let ordinal = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        let afterDot = rest.dropFirst()
        guard rest.first == orderedSuffix, afterDot.first == markerGap else { return nil }
        return ListItem(ordinal: ordinal, text: String(afterDot.dropFirst()))
    }
}
