import Foundation

/// A stretch a timer ran, to the second: from when it was started to when it was stopped, or up to now while it runs.
public struct TimerSession: Codable, Hashable, Sendable {
    public var categoryID: String
    public var start: Date
    public var end: Date

    public init(categoryID: String, start: Date, end: Date) {
        self.categoryID = categoryID
        self.start = start
        self.end = end
    }

    /// A stretch shorter than this was a slip, such as a timer stopped as soon as it started, and logs nothing.
    public static let shortest: TimeInterval = 10

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    /// The blocks of `day` it ran during, any part of each, counted from `schedule`'s wake time; at least the block it
    /// started in. Empty when it ran on other days, or only before wake time.
    public func blocks(on day: String, schedule: Schedule, calendar: Calendar = .current) -> Range<Int> {
        guard let wake = DayID.date(of: schedule.wakeMinute, on: day, calendar: calendar),
              let dayEnd = DayID.date(of: 24 * 60 + schedule.rolloverMinute, on: day, calendar: calendar)
        else { return 0..<0 }
        let seconds = Double(Schedule.blockMinutes * 60)
        let first = Int((start.timeIntervalSince(wake) / seconds).rounded(.down))
        let last = Int((min(end, dayEnd).timeIntervalSince(wake) / seconds).rounded(.up))
        let lower = max(0, first)
        let upper = min(max(last, first + 1), Int((dayEnd.timeIntervalSince(wake) / seconds).rounded(.down)))
        return lower < upper ? lower..<upper : lower..<lower
    }
}

/// Logs an activity live: while it runs, every block it runs in holds its activity, alongside whatever else the block
/// holds. It counts up from zero, or down from a length and then on past zero, until it's stopped.
public struct LiveTimer: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let categoryID: String
    /// What it counts down from, in seconds, or nil to count up.
    public let countdown: TimeInterval?
    public let startedAt: Date

    public init(id: UUID = UUID(), categoryID: String, countdown: TimeInterval? = nil, startedAt: Date) {
        self.id = id
        self.categoryID = categoryID
        self.countdown = countdown
        self.startedAt = startedAt
    }

    /// How long it has run.
    public func elapsed(at date: Date) -> TimeInterval {
        max(0, date.timeIntervalSince(startedAt))
    }

    /// The time left on a countdown, below zero once it's over; nil for a timer counting up.
    public func remaining(at date: Date) -> TimeInterval? {
        countdown.map { $0 - elapsed(at: date) }
    }

    /// When a countdown gets to zero, which can have passed.
    public var zeroDate: Date? {
        countdown.map { startedAt.addingTimeInterval($0) }
    }

    /// What it has run, up to `date`.
    public func session(at date: Date) -> TimerSession {
        TimerSession(categoryID: categoryID, start: startedAt, end: max(startedAt, date))
    }
}

/// Keeps the timers going between launches, where the widget can see them, beside the settings.
public enum TimerStore {
    private static let key = "timers"

    public static func load() -> [LiveTimer] {
        guard let data = AppGroup.defaults.data(forKey: key),
              let timers = try? JSONDecoder().decode([LiveTimer].self, from: data)
        else { return [] }
        return timers
    }

    public static func save(_ timers: [LiveTimer]) {
        guard let data = try? JSONEncoder().encode(timers) else { return }
        AppGroup.defaults.set(data, forKey: key)
    }
}

/// A countdown's length, in minutes, as shown: "30 min", "1 h", "1 h 30 min".
public enum CountdownLength {
    /// What countdowns start at until another default is set.
    public static let standard = 30
    /// The lengths to pick in a click until others are starred.
    public static let standardPresets = [30, 60]
    /// The longest a countdown can be set to.
    public static let longest = 24 * 60

    /// The blocks a countdown of `minutes` takes, any part of one counting, as a timer logs them: 21 minutes is 5.
    public static func blocks(_ minutes: Int) -> Int {
        (minutes + Schedule.blockMinutes - 1) / Schedule.blockMinutes
    }

    public static func text(_ minutes: Int) -> String {
        let (hours, rest) = (minutes / 60, minutes % 60)
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}
