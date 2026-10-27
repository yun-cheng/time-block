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
    /// The end you set a time for; the other follows it or stays. Editing the shift starts from it again.
    public var leads: Schedule.End
    /// Whether you set the day to be there by rather than the day to start.
    public var isByFinishDay: Bool

    public init(
        from: Schedule, startDay: String, stepMinutes: Int = 30, everyDays: Int = 1, leads: Schedule.End = .bed
    ) {
        self.from = from
        self.startDay = startDay
        self.stepMinutes = stepMinutes
        self.everyDays = everyDays
        self.leads = leads
        isByFinishDay = false
    }

    /// A shift that has you on `target` from `finishDay`, starting as many steps before it as it takes.
    public init(
        from: Schedule, finishingOn finishDay: String, target: Schedule, stepMinutes: Int = 30, everyDays: Int = 1,
        leads: Schedule.End = .bed, calendar: Calendar = .current
    ) {
        self.init(from: from, startDay: finishDay, stepMinutes: stepMinutes, everyDays: everyDays, leads: leads)
        startDay = restarted(finishingOn: finishDay, target: target, calendar: calendar)
        isByFinishDay = true
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = try container.decode(Schedule.self, forKey: .from)
        startDay = try container.decode(String.self, forKey: .startDay)
        stepMinutes = try container.decode(Int.self, forKey: .stepMinutes)
        everyDays = try container.decode(Int.self, forKey: .everyDays)
        // Shifts saved before these were kept went by bedtime and a start day.
        leads = try container.decodeIfPresent(Schedule.End.self, forKey: .leads) ?? .bed
        isByFinishDay = try container.decodeIfPresent(Bool.self, forKey: .isByFinishDay) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case from, startDay, stepMinutes, everyDays, leads, isByFinishDay
    }

    /// The schedule on `day`: wake time after the steps taken by the night before, bedtime after the steps taken
    /// by its own night.
    public func schedule(on day: String, target: Schedule, calendar: Calendar = .current) -> Schedule {
        let lastNight = DayID.adding(-1, to: day, calendar: calendar) ?? day
        return Schedule(
            wakeMinute: schedule(afterSteps: steps(on: lastNight, calendar: calendar), target: target).wakeMinute,
            bedMinute: schedule(afterSteps: steps(on: day, calendar: calendar), target: target).bedMinute)
    }

    /// Where the shift has got to by the morning of `day`: the steps taken by the night before. Tonight's step
    /// moves on from here.
    public func position(on day: String, target: Schedule, calendar: Calendar = .current) -> Schedule {
        schedule(afterSteps: steps(on: DayID.adding(-1, to: day, calendar: calendar) ?? day, calendar: calendar), target: target)
    }

    /// Whether the night of `day` takes a step that moves its bedtime or the next morning's wake time.
    public func movesOnNight(of day: String, target: Schedule, calendar: Calendar = .current) -> Bool {
        schedule(afterSteps: steps(on: day, calendar: calendar), target: target)
            != position(on: day, target: target, calendar: calendar)
    }

    /// The first night from `day` on that takes a step, going by `everyDays`.
    public func nextStepDay(from day: String, calendar: Calendar = .current) -> String {
        guard let days = DayID.days(from: startDay, to: day, calendar: calendar), days > 0 else { return startDay }
        let every = max(1, everyDays)
        return DayID.adding((days + every - 1) / every * every, to: startDay, calendar: calendar) ?? day
    }

    /// The shift carried on from where it's got to by the morning of `today`, with its next step on the night of
    /// `day`: today's morning stays, and nothing before it changes that you'd still see. Later than tonight holds
    /// the steps back a night or more, say after sleeping in.
    public func resumed(
        today: String, nextStepOn day: String, target: Schedule, calendar: Calendar = .current
    ) -> SleepShift {
        var shift = self
        shift.from = position(on: today, target: target, calendar: calendar)
        shift.startDay = day
        return shift
    }

    /// The shift carried on from `schedule` as the times of `day`, say after sleeping in or before it starts: it
    /// keeps its target, step and pace, and takes its next step from the next night on, keeping its finish day when
    /// that's what you set.
    public func rebased(
        onto schedule: Schedule, on day: String, target: Schedule, calendar: Calendar = .current
    ) -> SleepShift {
        let tomorrow = DayID.adding(1, to: day, calendar: calendar) ?? day
        var shift = self
        shift.from = schedule
        shift.startDay = isByFinishDay
            ? shift.restarted(finishingOn: finishDay(target: target, calendar: calendar), target: target, calendar: calendar)
            : nextStepDay(from: tomorrow, calendar: calendar)
        if (DayID.days(from: tomorrow, to: shift.startDay, calendar: calendar) ?? 0) < 0 { shift.startDay = tomorrow }
        return shift
    }

    /// The start day that gets this shift to `target` by `finishDay`.
    private func restarted(finishingOn finishDay: String, target: Schedule, calendar: Calendar) -> String {
        DayID.adding(-daysToFinish(target: target), to: finishDay, calendar: calendar) ?? finishDay
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
    public enum End: String, Codable, Hashable, Sendable {
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
