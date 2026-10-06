import Foundation

/// Shared date encoding for persisted rows. A fresh formatter is created per call since
/// `ISO8601DateFormatter` is not `Sendable` and these calls are cheap and infrequent.
enum ISO8601Format {
    private static func makeFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    static func string(from date: Date) -> String {
        makeFormatter().string(from: date)
    }

    static func date(from string: String) -> Date? {
        makeFormatter().date(from: string)
    }
}
