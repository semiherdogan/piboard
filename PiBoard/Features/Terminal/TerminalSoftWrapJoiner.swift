import Foundation

private let trailingWhitespaceCharacters = CharacterSet(charactersIn: " \t\u{00A0}")
private let space: Character = " "
private let joinSeparator = " "
private let bulletMarkers: Set<Character> = ["-", "*", "+", "•", "⏺", "●", ">"]
private let orderedListTerminators: Set<Character> = [".", ")"]
private let codeFence = "```"
private let headingMarker: Character = "#"
private let tableBorder: Character = "|"
private let boxDrawingScalars: ClosedRange<Unicode.Scalar> = "\u{2500}"..."\u{257F}"

/// Rejoins lines an agent's TUI broke at the screen width. Pi, Claude Code and OpenCode wrap text
/// themselves and send hard newlines, so the terminal has no wrap marker to rejoin on; a line is
/// treated as wrapped when the next line's first word could not have fit after it. A guess by
/// design: lists, headings, tables, fences and box borders are left alone.
enum TerminalSoftWrapJoiner {
    /// Widest right margin an agent leaves before wrapping; Pi pads one column, Claude Code a few.
    static let maximumRightMargin = 4
    /// Pi pads one column; a word cut mid-word fills the row up to it.
    static let fullRowMargin = 1

    /// `firstLineStartColumn` is where the selection begins on its first row, because the first
    /// line of a selection is usually partial and its length alone does not say where it ends.
    static func join(_ text: String?, columns: Int, firstLineStartColumn: Int) -> String {
        guard let text, columns > 0 else { return TerminalTextTrimmer.trim(text) }

        let rows = text.components(separatedBy: .newlines).enumerated().map { index, line in
            Row(text: trimTrailingWhitespace(line), startColumn: index == 0 ? firstLineStartColumn : 0, columns: columns)
        }

        var output: [String] = []
        var previous: Row?
        var contentIndent: Int?
        for row in rows {
            if let last = previous, let logical = output.indices.last,
                continues(last, with: row, contentIndent: contentIndent, columns: columns)
            {
                output[logical] += separator(after: last, contentIndent: contentIndent, columns: columns) + row.body
            } else {
                output.append(row.text)
                contentIndent = row.continuationIndent
            }
            previous = row
        }
        return TerminalTextTrimmer.trim(output.joined(separator: "\n"))
    }

    private static func continues(_ row: Row, with next: Row, contentIndent: Int?, columns: Int) -> Bool {
        guard !row.body.isEmpty, !next.body.isEmpty,
            !row.hasBorder, !next.hasBorder, !next.startsBlock
        else { return false }
        if let contentIndent, next.indentColumn != contentIndent { return false }
        return row.endColumn + joinSeparator.count + next.firstWordWidth > columns - maximumRightMargin
    }

    /// A word longer than the line is cut mid-word, which shows as a row filled to `fullRowMargin`
    /// with no space after the indent; those pieces join without a space. Unknown indent means no way to tell, so a space.
    private static func separator(after row: Row, contentIndent: Int?, columns: Int) -> String {
        guard let contentIndent else { return joinSeparator }
        let reachesEdge = row.endColumn >= columns - fullRowMargin
        let ownText = row.text.dropFirst(max(0, contentIndent - row.startColumn))
        return reachesEdge && !ownText.contains(space) ? "" : joinSeparator
    }

    private static func trimTrailingWhitespace(_ line: String) -> String {
        var trimmed = Substring(line)
        while let last = trimmed.unicodeScalars.last, trailingWhitespaceCharacters.contains(last) {
            trimmed = trimmed.dropLast()
        }
        return String(trimmed)
    }
}

private struct Row {
    let text: String
    let startColumn: Int
    let body: Substring
    let indentColumn: Int
    let endColumn: Int

    init(text: String, startColumn: Int, columns: Int) {
        self.text = text
        self.startColumn = startColumn
        body = text.drop(while: { $0 == space })
        indentColumn = startColumn + text.count - body.count
        // SwiftTerm already merges rows the terminal itself wrapped, so only the last row counts.
        let end = startColumn + text.count
        endColumn = end > columns ? (end - 1) % columns + 1 : end
    }

    var firstWordWidth: Int {
        body.prefix(while: { $0 != space }).count
    }

    /// Where the next row has to start to continue this one: past a list marker when there is one.
    /// A selection that starts mid-row without leading spaces hides the real indent, so nil (any).
    var continuationIndent: Int? {
        guard startColumn == 0 || indentColumn > startColumn else { return nil }
        return indentColumn + (listMarkerWidth ?? 0)
    }

    var startsBlock: Bool {
        guard let first = body.first else { return false }
        return listMarkerWidth != nil || isCodeFence || isHeading || first == tableBorder || first.isBoxDrawing
    }

    private var isCodeFence: Bool {
        body.hasPrefix(codeFence)
    }

    private var isHeading: Bool {
        body.drop(while: { $0 == headingMarker }).first == space && body.first == headingMarker
    }

    var hasBorder: Bool {
        guard let first = body.first, let last = body.last else { return false }
        return first.isBoxDrawing || last.isBoxDrawing || first == tableBorder || last == tableBorder
    }

    /// Width of "- ", "⏺ " or "12. " including the space after it, or nil when the row is not a list item.
    private var listMarkerWidth: Int? {
        let afterMarker: Substring
        if let first = body.first, bulletMarkers.contains(first) {
            afterMarker = body.dropFirst()
        } else {
            let digits = body.prefix(while: \.isASCIIDigit)
            guard !digits.isEmpty, let terminator = body.dropFirst(digits.count).first,
                orderedListTerminators.contains(terminator)
            else { return nil }
            afterMarker = body.dropFirst(digits.count).dropFirst()
        }
        guard afterMarker.first == space else { return nil }
        return body.count - afterMarker.dropFirst().count
    }
}

private extension Character {
    var isBoxDrawing: Bool {
        unicodeScalars.first.map { boxDrawingScalars.contains($0) } ?? false
    }

    var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
