import Foundation

/// A moment as a clock time, as short as it can be while staying unambiguous.
enum ClockTimestamp {
    /// Days back that still read as a weekday; older dates would repeat a weekday name.
    static let weekdayWindowDays = 6

    static func short(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        func style() -> Date.FormatStyle {
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        }
        let daysBack = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        if daysBack == 0 {
            return date.formatted(style().hour().minute())
        }
        if (1...weekdayWindowDays).contains(daysBack) {
            return date.formatted(style().weekday(.abbreviated).hour().minute())
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(style().day().month(.defaultDigits).hour().minute())
        }
        return date.formatted(style().day().month(.defaultDigits).year().hour().minute())
    }

    static func full(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        date.formatted(Date.FormatStyle(date: .complete, time: .shortened, locale: locale, timeZone: timeZone))
    }
}
