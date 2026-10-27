import Foundation

/// A notification the day has coming: a routine starting, winding down, bedtime, or getting later past it.
public struct Reminder: Hashable, Sendable {
    /// Stays the same while what it says about stays put, so planning again replaces it rather than adding another.
    public let id: String
    public let date: Date
    public let title: String
    public let body: String

    public init(id: String, date: Date, title: String, body: String) {
        self.id = id
        self.date = date
        self.title = title
        self.body = body
    }

    /// What every reminder's id starts with, telling them apart from timers' alarms.
    public static let idPrefix = "reminder-"

    /// Minutes past bedtime to say so again, as the day turns to dread and then to nightmare.
    public static let pastBedtimeMinutes = [30, 120]
}

extension AppSettings {
    /// What `log`'s day has to notify you of after `date`, in order: the routines that notify, where they're still
    /// pre-logged, winding down and bedtime, and how far past bedtime it's got.
    public func reminders(for log: DayLog, after date: Date, calendar: Calendar = .current) -> [Reminder] {
        var log = log
        let schedule = schedule(on: log.day, calendar: calendar)
        log.rebase(to: schedule)
        let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let clock = { (block: Int) in Self.clock(schedule.clockMinute(ofBlock: block)) }
        var reminders: [(block: Int, id: String, title: String, body: String)] = []

        for template in templates where template.notifies {
            let ranges = template.anchor == .after
                ? log.ends(of: template).map { template.range(in: schedule, following: $0) }
                : [template.range(in: schedule)]
            let held = Set(log.logs.filter { $0.templateID == template.id }.flatMap(\.range))
            for range in ranges {
                // Where it's still pre-logged: after anything that took its first blocks, and not at all when you
                // logged over the whole of it.
                guard let start = range.first(where: held.contains) else { continue }
                let end = range.last(where: held.contains).map { $0 + 1 } ?? range.upperBound
                reminders.append((
                    start, "\(template.id)-\(start)", names[template.categoryID] ?? "Routine",
                    "\(clock(start))–\(clock(end)), from your routine."))
            }
        }

        let bed = schedule.awakeBlocks
        if notifiesWindDown, windDownBlocks > 0 {
            let start = max(0, bed - windDownBlocks)
            reminders.append((
                start, "wind-down", "Time to wind down", "Bedtime is at \(clock(bed)). Get ready for sleep."))
        }
        if notifiesBedtime {
            let ahead = bedtimeNoticeMinutes / Schedule.blockMinutes
            let notice = max(0, bed - ahead)
            if ahead == 0 {
                reminders.append((
                    bed, "bedtime", "It's bedtime", "\(clock(bed)). Every block from now on is taken from sleep."))
            } else if !(notifiesWindDown && windDownBlocks > 0 && notice == max(0, bed - windDownBlocks)) {
                // Coming as winding down starts, that says it already.
                reminders.append((
                    notice, "bedtime", "Bedtime in \(Self.duration(minutes: (bed - notice) * Schedule.blockMinutes))",
                    "At \(clock(bed)). Time to finish up and get ready for sleep."))
            }
            for minutes in Reminder.pastBedtimeMinutes {
                let block = bed + minutes / Schedule.blockMinutes
                let past = minutes < 60 ? "\(minutes) minutes" : "\(minutes / 60) hours"
                reminders.append((
                    block, "past-bedtime-\(minutes)", "\(past) past bedtime",
                    minutes < 60 ? "\(past) taken from sleep so far. Stop now." : "You are borrowing from tomorrow."))
            }
        }

        return reminders.compactMap { reminder in
            guard let at = DayID.date(of: schedule.wakeMinute + reminder.block * Schedule.blockMinutes, on: log.day,
                                      calendar: calendar), at > date else { return nil }
            return Reminder(
                id: "\(Reminder.idPrefix)\(log.day)-\(reminder.id)", date: at, title: reminder.title,
                body: reminder.body)
        }
        .sorted { $0.date < $1.date }
    }

    /// "45 minutes", "1 hour", "1h 30m".
    private static func duration(minutes: Int) -> String {
        switch (minutes / 60, minutes % 60) {
        case (0, let m): "\(m) minutes"
        case (1, 0): "1 hour"
        case (let h, 0): "\(h) hours"
        case (let h, let m): "\(h)h \(m)m"
        }
    }

    private static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60 % 24, minute % 60)
    }
}
