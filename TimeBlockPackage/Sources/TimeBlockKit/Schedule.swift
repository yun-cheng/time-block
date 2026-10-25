import Foundation

/// A day's waking window. Times are minutes after midnight.
public struct Schedule: Hashable, Codable, Sendable {
    public static let blockMinutes = 5
    public static let blocksPerHour = 60 / blockMinutes

    public var wakeMinute: Int
    /// A bedtime at or before `wakeMinute` is read as after midnight (e.g. 01:00).
    public var bedMinute: Int
    /// Clock times before this still belong to the previous day, so 01:30 counts as "tonight", not tomorrow.
    public var rolloverMinute: Int

    public init(wakeMinute: Int, bedMinute: Int, rolloverMinute: Int? = nil) {
        self.wakeMinute = wakeMinute
        self.bedMinute = bedMinute
        self.rolloverMinute = rolloverMinute ?? max(0, wakeMinute - 120)
    }

    /// Snaps a time picker edit to a block boundary. Time pickers step minutes by one, so a ±1 minute change
    /// from a block boundary (including the picker wrapping :00 down to :59) is a step to the next block;
    /// anything else, like a typed time, rounds to the nearest block.
    public static func snappedMinute(editing old: Int, to new: Int) -> Int {
        let day = 24 * 60
        let snapped = switch new - old {
        case 1, -59: old + blockMinutes
        case -1, 59: old - blockMinutes
        default: (new + blockMinutes / 2) / blockMinutes * blockMinutes
        }
        return (snapped % day + day) % day
    }

    public static let standard = Schedule(wakeMinute: 7 * 60, bedMinute: 23 * 60)

    /// Bedtime on the day's timeline, which keeps counting past midnight (01:00 → 1500).
    public var bedTimelineMinute: Int {
        bedMinute > wakeMinute ? bedMinute : bedMinute + 24 * 60
    }

    public var awakeBlocks: Int {
        (bedTimelineMinute - wakeMinute) / Schedule.blockMinutes
    }

    /// Empty slots before the first block, so grid rows line up with clock hours (08:30 wake → 6).
    public var gridOffset: Int {
        (wakeMinute % 60) / Schedule.blockMinutes
    }

    /// Clock hour (0–23) of a grid row whose rows line up with clock hours.
    public func hour(ofRow row: Int) -> Int {
        (wakeMinute / 60 + row) % 24
    }

    public func timelineMinute(clockMinute: Int) -> Int {
        clockMinute < rolloverMinute ? clockMinute + 24 * 60 : clockMinute
    }

    public func timelineMinute(for date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return timelineMinute(clockMinute: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    /// The day a moment belongs to, as "2026-10-24". Before the rollover it is still the previous day.
    public func dayID(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let clockMinute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let day = clockMinute < rolloverMinute ? calendar.date(byAdding: .day, value: -1, to: date) ?? date : date
        return DayID.string(from: day, calendar: calendar)
    }

    /// Index of the block containing a clock time, counted from wake time.
    public func blockIndex(clockMinute: Int) -> Int {
        let offset = timelineMinute(clockMinute: clockMinute) - wakeMinute
        return Int((Double(offset) / Double(Schedule.blockMinutes)).rounded(.down))
    }

    /// Clock minute (0..<1440) at which a block starts.
    public func clockMinute(ofBlock index: Int) -> Int {
        (wakeMinute + index * Schedule.blockMinutes) % (24 * 60)
    }
}
