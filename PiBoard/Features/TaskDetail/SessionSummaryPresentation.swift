import Foundation

enum SessionSummaryPresentation {
    private static let costCurrencyCode = "USD"
    private static let thousand = 1_000
    private static let million = 1_000_000
    private static let thousandSuffix = "k"
    private static let millionSuffix = "M"
    private static let compactFractionDigits = 1
    private static let posixLocaleIdentifier = "en_US_POSIX"
    // Below a narrow terminal's width, so the search term stays on one screen line.
    private static let promptSearchLength = 40
    // A shorter leftover of a stripped line matches too much of an agent's own output; a typed line is always kept.
    private static let promptSearchMinimumLength = 6
    // A single- or double-quoted span with a slash in it, such as a dropped file's path.
    private static let quotedPathPattern = #"(['"])[^'"]*/[^'"]*\1"#
    private static let promptSearchLineLimit = 5
    // A word with one of these is a path or a link, which agents tend to render differently.
    private static let promptPathMarkers = ["/", "://"]
    // Left at the ends once a quoted path is gone, such as a stray quote or the `;` after it.
    private static let promptSearchTrimCharacters = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "'\";,:"))

    /// "12.3k in, 1.2k out" style; cache tokens are folded into the input figure the way Pi's footer does.
    static func tokens(_ usage: SessionSummary.Usage) -> String {
        "\(compact(usage.input + usage.cacheRead + usage.cacheWrite)) in, \(compact(usage.output)) out"
    }

    static func turns(_ count: Int) -> String {
        count == 1 ? "1 turn" : "\(count) turns"
    }

    /// Model, turns, tokens and, when the provider reports one, cost: the right side of the terminal's info strip.
    static func stripDetails(_ summary: SessionSummary) -> [String] {
        var details: [String] = []
        if let model = summary.model { details.append(model) }
        details.append(turns(summary.turnCount))
        details.append(tokens(summary.usage))
        if summary.usage.cost > 0 { details.append(cost(summary.usage.cost)) }
        return details
    }

    /// What to search the terminal for, best guess first: the start of each line as typed, then the
    /// same line without paths and links, which agents often show as an attachment instead of the text.
    static func promptSearchTerms(_ prompt: String) -> [String] {
        let lines = prompt.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(promptSearchLineLimit)
        var terms: [String] = []
        for line in lines {
            let typed = String(line.prefix(promptSearchLength))
            if !terms.contains(typed) { terms.append(typed) }
            let stripped = String(withoutPaths(line).prefix(promptSearchLength))
            if stripped.count >= promptSearchMinimumLength, !terms.contains(stripped) { terms.append(stripped) }
        }
        return terms
    }

    // Quoted paths go as a whole first, as dropped files are quoted and file names often have spaces.
    private static func withoutPaths(_ line: String) -> String {
        let unquoted = line.replacingOccurrences(of: quotedPathPattern, with: " ", options: .regularExpression)
        return unquoted.split(separator: " ")
            .filter { word in !promptPathMarkers.contains { word.contains($0) } }
            .joined(separator: " ")
            .trimmingCharacters(in: promptSearchTrimCharacters)
    }

    /// A session that has not had a turn yet has nothing worth a line above the terminal.
    static func hasStripContent(_ summary: SessionSummary) -> Bool {
        summary.turnCount > 0 || summary.lastAssistantText != nil
    }

    /// Pinned to POSIX so the figure reads the same everywhere; it is a provider estimate, not an invoice.
    static func cost(_ cost: Double) -> String {
        cost.formatted(.currency(code: costCurrencyCode).precision(.fractionLength(2...4)).locale(Locale(identifier: posixLocaleIdentifier)))
    }

    /// 950 -> "950", 12_345 -> "12.3k", 2_345_678 -> "2.3M".
    static func compact(_ count: Int) -> String {
        switch count {
        case million...:
            return scaled(count, by: million, suffix: millionSuffix)
        case thousand...:
            return scaled(count, by: thousand, suffix: thousandSuffix)
        default:
            return String(count)
        }
    }

    private static func scaled(_ count: Int, by divisor: Int, suffix: String) -> String {
        (Double(count) / Double(divisor)).formatted(.number.precision(.fractionLength(compactFractionDigits)).locale(Locale(identifier: posixLocaleIdentifier))) + suffix
    }
}
