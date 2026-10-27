import Foundation

/// Days as "2026-10-26", the way `Schedule.dayID` writes them.
public enum DayID {
    public static func date(_ day: String, calendar: Calendar = .current) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        // Noon, clear of daylight saving changes.
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// The moment a minute of `day`'s timeline comes (see `Schedule.timelineMinute`), which counts on past midnight.
    /// Read off the clock, so it's right on days the clocks change.
    public static func date(of timelineMinute: Int, on day: String, calendar: Calendar = .current) -> Date? {
        date(day, calendar: calendar)
            .flatMap { calendar.date(byAdding: .day, value: timelineMinute / (24 * 60), to: $0) }
            .flatMap {
                let minute = timelineMinute % (24 * 60)
                return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: $0)
            }
    }

    public static func string(from date: Date, calendar: Calendar = .current) -> String {
        let ymd = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", ymd.year ?? 0, ymd.month ?? 0, ymd.day ?? 0)
    }

    public static func adding(_ days: Int, to day: String, calendar: Calendar = .current) -> String? {
        date(day, calendar: calendar).flatMap { calendar.date(byAdding: .day, value: days, to: $0) }
            .map { string(from: $0, calendar: calendar) }
    }

    public static func days(from start: String, to end: String, calendar: Calendar = .current) -> Int? {
        guard let start = date(start, calendar: calendar), let end = date(end, calendar: calendar) else { return nil }
        return calendar.dateComponents([.day], from: start, to: end).day
    }
}
