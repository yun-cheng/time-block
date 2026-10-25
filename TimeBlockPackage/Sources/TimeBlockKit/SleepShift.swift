import Foundation

/// Gets you to your schedule a step at a time instead of all at once: bedtime 01:00 to 23:00, 30 minutes a day,
/// is 00:30, 00:00, 23:30, then 23:00. The schedule in `AppSettings` is where you're heading; `from` is where you
/// started, and each day's schedule is a few steps along from it.
///
/// Steps land on nights: the step on a day moves that day's bedtime, and wake time follows the next morning, so
/// the night between them is as long as before. A morning that's already gone never moves.
public struct SleepShift: Codable, Hashable, Sendable {
    /// The schedule you started from.
    public var from: Schedule
    /// The day whose night takes the first step, as "2026-10-26" (see `Schedule.dayID`).
    public var startDay: String
    /// How far wake time and bedtime move each step, in minutes: a multiple of a block.
    public var stepMinutes: Int
    /// Days between steps.
    public var everyDays: Int

    public init(from: Schedule, startDay: String, stepMinutes: Int = 30, everyDays: Int = 1) {
        self.from = from
        self.startDay = startDay
        self.stepMinutes = stepMinutes
        self.everyDays = everyDays
    }

    /// A shift that has you on `target` from `finishDay`, starting as many steps before it as it takes.
    public init(
        from: Schedule, finishingOn finishDay: String, target: Schedule, stepMinutes: Int = 30, everyDays: Int = 1,
        calendar: Calendar = .current
    ) {
        self.init(from: from, startDay: finishDay, stepMinutes: stepMinutes, everyDays: everyDays)
        startDay = DayID.adding(-daysToFinish(target: target), to: finishDay, calendar: calendar) ?? finishDay
    }

    /// The schedule on `day`: wake time after the steps taken by the night before, bedtime after the steps taken
    /// by its own night.
    public func schedule(on day: String, target: Schedule, calendar: Calendar = .current) -> Schedule {
        let lastNight = DayID.adding(-1, to: day, calendar: calendar) ?? day
        return Schedule(
            wakeMinute: schedule(afterSteps: steps(on: lastNight, calendar: calendar), target: target).wakeMinute,
            bedMinute: schedule(afterSteps: steps(on: day, calendar: calendar), target: target).bedMinute)
    }

    /// Where `steps` steps from `from` toward `target` get you. Wake time and bedtime each stop once they get there.
    public func schedule(afterSteps steps: Int, target: Schedule) -> Schedule {
        let moved = steps * stepMinutes
        let toward = { (from: Int, to: Int) in
            let distance = Self.distance(from: from, to: to)
            return Self.clock(from + distance.signum() * min(abs(distance), moved))
        }
        return Schedule(
            wakeMinute: toward(from.wakeMinute, target.wakeMinute), bedMinute: toward(from.bedMinute, target.bedMinute))
    }

    /// How many steps have been taken by the night of `day`: none before `startDay`, then one more every
    /// `everyDays`.
    public func steps(on day: String, calendar: Calendar = .current) -> Int {
        guard let days = DayID.days(from: startDay, to: day, calendar: calendar), days >= 0 else { return 0 }
        return days / max(1, everyDays) + 1
    }

    /// Steps it takes to get from `from` to `target`.
    public func stepCount(to target: Schedule) -> Int {
        max(steps(across: from.wakeMinute, target.wakeMinute), steps(across: from.bedMinute, target.bedMinute))
    }

    /// The first day that's all on `target`: the day of the last bedtime step, or the morning after the last wake
    /// time step.
    public func finishDay(target: Schedule, calendar: Calendar = .current) -> String {
        DayID.adding(daysToFinish(target: target), to: startDay, calendar: calendar) ?? startDay
    }

    /// Whether `day` is on `target` already, so the shift is over.
    public func isDone(on day: String, target: Schedule, calendar: Calendar = .current) -> Bool {
        (DayID.days(from: finishDay(target: target, calendar: calendar), to: day, calendar: calendar) ?? 0) >= 0
    }

    /// Days from `startDay` to `finishDay`.
    private func daysToFinish(target: Schedule) -> Int {
        let nightOfStep = { (step: Int) in (step - 1) * max(1, everyDays) }
        let bed = steps(across: from.bedMinute, target.bedMinute)
        let wake = steps(across: from.wakeMinute, target.wakeMinute)
        return max(bed > 0 ? nightOfStep(bed) : 0, wake > 0 ? nightOfStep(wake) + 1 : 0)
    }

    private func steps(across from: Int, _ to: Int) -> Int {
        let step = max(Schedule.blockMinutes, stepMinutes)
        return (abs(Self.distance(from: from, to: to)) + step - 1) / step
    }

    /// The shortest way round the clock from one time to another, in minutes: 01:00 to 23:00 is -120.
    public static func distance(from: Int, to: Int) -> Int {
        let day = 24 * 60
        return ((to - from) % day + day + day / 2) % day - day / 2
    }

    private static func clock(_ minute: Int) -> Int {
        (minute % (24 * 60) + 24 * 60) % (24 * 60)
    }
}

extension Schedule {
    /// One end of the waking day.
    public enum End: Hashable, Sendable {
        case wake, bed
    }

    /// This schedule with one end moved to `minute`, and the other moved as far when `keepsSleep`, so you sleep as
    /// long as before.
    public func moving(_ end: End, to minute: Int, keepsSleep: Bool) -> Schedule {
        let moved = SleepShift.distance(from: end == .wake ? wakeMinute : bedMinute, to: minute)
        let move = { (time: Int) in ((time + moved) % (24 * 60) + 24 * 60) % (24 * 60) }
        return switch end {
        case .wake: Schedule(wakeMinute: minute, bedMinute: keepsSleep ? move(bedMinute) : bedMinute)
        case .bed: Schedule(wakeMinute: keepsSleep ? move(wakeMinute) : wakeMinute, bedMinute: minute)
        }
    }
}

/// Days as "2026-10-26", the way `Schedule.dayID` writes them.
public enum DayID {
    public static func date(_ day: String, calendar: Calendar = .current) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        // Noon, clear of daylight saving changes.
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
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
