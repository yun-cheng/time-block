/// How the UI should feel, driven by how many blocks are left before bedtime.
public enum Mood: Int, Comparable, CaseIterable, Sendable {
    case calm
    /// The last 30 minutes before bed.
    case windDown
    /// Up to 30 minutes past bedtime.
    case uneasy
    /// Up to 2 hours past bedtime.
    case dread
    /// More than 2 hours past bedtime.
    case nightmare

    public init(blocksLeft: Int) {
        switch blocksLeft {
        case 7...: self = .calm
        case 1...6: self = .windDown
        case -6...0: self = .uneasy
        case -24 ... -7: self = .dread
        default: self = .nightmare
        }
    }

    public static func < (lhs: Mood, rhs: Mood) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Where "now" sits in a day's blocks.
public struct DayStatus: Hashable, Sendable {
    public let schedule: Schedule
    /// Minute on the day's timeline (see `Schedule.timelineMinute`).
    public let nowMinute: Int

    public init(schedule: Schedule, nowMinute: Int) {
        self.schedule = schedule
        self.nowMinute = nowMinute
    }

    /// The block in progress, counted from wake time; nil before waking.
    public var currentIndex: Int? {
        nowMinute >= schedule.wakeMinute ? (nowMinute - schedule.wakeMinute) / Schedule.blockMinutes : nil
    }

    /// Blocks that have fully passed since waking, including any past bedtime.
    public var blocksUsed: Int { currentIndex ?? 0 }

    /// Blocks started after bedtime, including the one in progress.
    public var overtimeBlocks: Int {
        max(0, (currentIndex ?? 0) - schedule.awakeBlocks + 1)
    }

    /// Blocks left before bedtime, counting the one in progress. Goes from 1 straight to -1 at bedtime,
    /// so a negative number is always the count of blocks taken from sleep.
    public var blocksLeft: Int {
        guard let index = currentIndex else { return schedule.awakeBlocks }
        return index < schedule.awakeBlocks ? schedule.awakeBlocks - index : -overtimeBlocks
    }

    public var mood: Mood { Mood(blocksLeft: blocksLeft) }

    /// Blocks the grid shows: the waking day plus any overtime already started.
    public var visibleBlocks: Int { schedule.awakeBlocks + overtimeBlocks }
}
