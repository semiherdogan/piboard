import Foundation
import Testing
@testable import PiBoard

struct ClockTimestampTests {
    private static let zone = TimeZone(identifier: "Europe/Istanbul")!
    private static let british = Locale(identifier: "en_GB")
    private static let turkish = Locale(identifier: "tr_TR")

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = british
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // Wednesday 2026-11-18 09:00.
    private static let now = date(2026, 11, 18, 9, 0)

    private func short(_ date: Date, locale: Locale = british) -> String {
        ClockTimestamp.short(date, now: Self.now, calendar: Self.calendar, locale: locale)
    }

    @Test func todayShowsTheTimeOnly() {
        #expect(short(Self.date(2026, 11, 18, 14, 30)) == "14:30")
    }

    @Test func aDateLaterTodayIsStillToday() {
        #expect(short(Self.date(2026, 11, 18, 23, 59)) == "23:59")
    }

    @Test func dayBoundaryIsMidnightNotTwentyFourHours() {
        #expect(short(Self.date(2026, 11, 17, 23, 59)) == "Tue 23:59")
        #expect(short(Self.date(2026, 11, 18, 0, 1)) == "00:01")
    }

    @Test func withinSixDaysShowsTheWeekday() {
        #expect(short(Self.date(2026, 11, 17, 14, 30)) == "Tue 14:30")
        #expect(short(Self.date(2026, 11, 12, 14, 30)) == "Thu 14:30")
    }

    @Test func sevenDaysBackShowsDayAndMonth() {
        #expect(short(Self.date(2026, 11, 11, 14, 30)) == "11/11, 14:30")
    }

    @Test func olderInTheSameYearFollowsTheLocalesOrder() {
        #expect(short(Self.date(2026, 3, 5, 14, 30)) == "05/03, 14:30")
        #expect(short(Self.date(2026, 3, 5, 14, 30), locale: Self.turkish) == "5.03 14:30")
    }

    @Test func anotherYearAddsTheYear() {
        #expect(short(Self.date(2025, 11, 13, 14, 30)) == "13/11/2025, 14:30")
        #expect(short(Self.date(2025, 11, 13, 14, 30), locale: Self.turkish) == "13.11.2025 14:30")
    }

    @Test func aFutureDayOnADifferentDateUsesTheDatedForm() {
        #expect(short(Self.date(2026, 11, 20, 8, 0)) == "20/11, 08:00")
    }

    private static var berlin: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.locale = british
        return calendar
    }

    private static func berlinDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        berlin.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func berlinShort(_ date: Date, now: Date) -> String {
        ClockTimestamp.short(date, now: now, calendar: Self.berlin, locale: Self.british)
    }

    // Berlin springs forward on Sunday 2026-03-29 (the day has 23 hours).
    @Test func springForwardDayKeepsCalendarDays() {
        let now = Self.berlinDate(2026, 3, 29, 12, 0)
        #expect(berlinShort(Self.berlinDate(2026, 3, 29, 1, 30), now: now) == "01:30")
        #expect(berlinShort(Self.berlinDate(2026, 3, 29, 3, 30), now: now) == "03:30")
        #expect(berlinShort(Self.berlinDate(2026, 3, 28, 23, 30), now: now) == "Sat 23:30")
        #expect(berlinShort(Self.berlinDate(2026, 3, 23, 12, 0), now: now) == "Mon 12:00")
        #expect(berlinShort(Self.berlinDate(2026, 3, 22, 12, 0), now: now) == "22/03, 12:00")
    }

    // Berlin falls back on Sunday 2026-10-25 (the day has 25 hours).
    @Test func fallBackDayKeepsCalendarDays() {
        let now = Self.berlinDate(2026, 10, 25, 12, 0)
        #expect(berlinShort(Self.berlinDate(2026, 10, 25, 1, 30), now: now) == "01:30")
        #expect(berlinShort(Self.berlinDate(2026, 10, 24, 23, 30), now: now) == "Sat 23:30")
        #expect(berlinShort(Self.berlinDate(2026, 10, 19, 12, 0), now: now) == "Mon 12:00")
        #expect(berlinShort(Self.berlinDate(2026, 10, 18, 12, 0), now: now) == "18/10, 12:00")
    }

    @Test func newYearsEveSeenOnNewYearsDayIsAWeekday() {
        let now = Self.date(2027, 1, 1, 9, 0)
        #expect(ClockTimestamp.short(Self.date(2026, 12, 31, 22, 0), now: now, calendar: Self.calendar, locale: Self.british) == "Thu 22:00")
    }

    @Test func lateDecemberSeenInJanuaryIncludesTheYear() {
        let now = Self.date(2027, 1, 2, 9, 0)
        #expect(ClockTimestamp.short(Self.date(2026, 12, 20, 10, 0), now: now, calendar: Self.calendar, locale: Self.british) == "20/12/2026, 10:00")
    }

    @Test func fullIncludesTheCompleteDate() {
        let text = ClockTimestamp.full(Self.date(2026, 11, 13, 14, 30), locale: Self.british, timeZone: Self.zone)
        #expect(text.contains("Friday"))
        #expect(text.contains("2026"))
        #expect(text.contains("14:30"))
    }
}
