/// A realistic day of logs for previews and the prototype.
public enum SampleDay {
    public static let categories = BlockCategory.defaults

    private struct Entry {
        let from: String
        let to: String
        let category: String
        let source: BlockLog.Source
        var note: String? = nil
    }

    // Gaps (07:50–08:00, 12:45–13:00, 15:15–15:30) are left unlogged on purpose.
    private static let entries: [Entry] = [
        Entry(from: "07:00", to: "07:30", category: "exercise", source: .manual),
        Entry(from: "07:30", to: "07:50", category: "breakfast", source: .template),
        Entry(from: "08:00", to: "08:30", category: "commute", source: .manual),
        Entry(from: "08:30", to: "10:00", category: "work", source: .manual),
        Entry(from: "10:00", to: "10:10", category: "coffee", source: .template),
        Entry(from: "10:10", to: "10:30", category: "work", source: .manual),
        Entry(from: "10:30", to: "11:00", category: "meeting", source: .calendar, note: "Standup"),
        Entry(from: "11:00", to: "12:00", category: "work", source: .manual),
        Entry(from: "12:00", to: "12:45", category: "lunch", source: .template),
        Entry(from: "13:00", to: "15:00", category: "work", source: .manual),
        Entry(from: "15:00", to: "15:15", category: "coffee", source: .template),
        Entry(from: "15:30", to: "16:30", category: "meeting", source: .calendar, note: "Design review"),
        Entry(from: "16:30", to: "18:00", category: "work", source: .manual),
        Entry(from: "18:00", to: "18:30", category: "commute", source: .manual),
        Entry(from: "18:30", to: "19:00", category: "rest", source: .manual),
        Entry(from: "19:00", to: "19:45", category: "dinner", source: .template),
        Entry(from: "19:45", to: "21:30", category: "social", source: .manual),
        Entry(from: "21:30", to: "02:59", category: "doomscroll", source: .manual),

        // Body track. 15:15–15:30 is left unlogged.
        Entry(from: "07:00", to: "07:30", category: "exercising", source: .manual),
        Entry(from: "07:30", to: "07:50", category: "sitting", source: .manual),
        Entry(from: "07:50", to: "08:00", category: "standing", source: .manual),
        Entry(from: "08:00", to: "08:10", category: "walking", source: .manual),
        Entry(from: "08:10", to: "08:25", category: "sitting", source: .manual),
        Entry(from: "08:25", to: "08:30", category: "walking", source: .manual),
        Entry(from: "08:30", to: "10:30", category: "sitting", source: .manual),
        Entry(from: "10:30", to: "11:00", category: "standing", source: .manual),
        Entry(from: "11:00", to: "12:45", category: "sitting", source: .manual),
        Entry(from: "12:45", to: "13:00", category: "walking", source: .manual, note: "Lunch walk"),
        Entry(from: "13:00", to: "15:00", category: "sitting", source: .manual),
        Entry(from: "15:00", to: "15:15", category: "standing", source: .manual),
        Entry(from: "15:30", to: "18:00", category: "sitting", source: .manual),
        Entry(from: "18:00", to: "18:10", category: "walking", source: .manual),
        Entry(from: "18:10", to: "18:30", category: "sitting", source: .manual),
        Entry(from: "18:30", to: "19:00", category: "lying", source: .manual),
        Entry(from: "19:00", to: "19:45", category: "sitting", source: .manual),
        Entry(from: "19:45", to: "20:30", category: "standing", source: .manual),
        Entry(from: "20:30", to: "21:30", category: "sitting", source: .manual),
        Entry(from: "21:30", to: "02:59", category: "lying", source: .manual, note: "Phone in bed"),
    ]

    public static func logs(schedule: Schedule, status: DayStatus) -> [BlockLog] {
        entries.compactMap { entry in
            let start = schedule.blockIndex(clockMinute: minute(entry.from))
            var end = schedule.blockIndex(clockMinute: minute(entry.to))
            if entry.source == .manual {
                // Manual logs only exist for time that has already happened.
                guard let current = status.currentIndex, start <= current else { return nil }
                end = min(end, current + 1)
            }
            guard end > start else { return nil }
            return BlockLog(
                startIndex: start, length: end - start, categoryID: entry.category,
                note: entry.note, source: entry.source)
        }
    }

    public static func snapshot(schedule: Schedule, nowMinute: Int, track: Track = .activity) -> DaySnapshot {
        let status = DayStatus(schedule: schedule, nowMinute: nowMinute)
        return DaySnapshot(
            status: status, logs: logs(schedule: schedule, status: status), categories: categories, track: track)
    }

    private static func minute(_ hhmm: String) -> Int {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        return parts[0] * 60 + parts[1]
    }
}
