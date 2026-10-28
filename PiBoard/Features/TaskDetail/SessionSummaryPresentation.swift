import Foundation

enum SessionSummaryPresentation {
    private static let costCurrencyCode = "USD"
    private static let thousand = 1_000
    private static let million = 1_000_000
    private static let thousandSuffix = "k"
    private static let millionSuffix = "M"
    private static let compactFractionDigits = 1
    private static let posixLocaleIdentifier = "en_US_POSIX"

    /// "12.3k in, 1.2k out" style; cache tokens are folded into the input figure the way Pi's footer does.
    static func tokens(_ usage: SessionSummary.Usage) -> String {
        "\(compact(usage.input + usage.cacheRead + usage.cacheWrite)) in, \(compact(usage.output)) out"
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
