/// How the UI should feel, driven by how many blocks are left before bedtime.
public enum Mood: Int, Comparable, CaseIterable, Sendable {
    case calm
    /// The last stretch before bed, set aside to get ready for sleep (30 minutes to start).
    case windDown
    /// Up to 30 minutes past bedtime.
    case uneasy
    /// Up to 2 hours past bedtime.
    case dread
    /// More than 2 hours past bedtime.
    case nightmare

    /// `windDownBlocks` is how many blocks before bed winding down takes; with none, calm lasts until bedtime.
    public init(blocksLeft: Int, windDownBlocks: Int = DayStatus.standardWindDownBlocks) {
        switch blocksLeft {
        case max(1, windDownBlocks + 1)...: self = .calm
        case 1...: self = .windDown
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
    /// Minute on the day's timeline (see `Schedule.timelineMinute`). For a day that's over, where it ended.
    public let nowMinute: Int
    /// Whether the day is over, a past day: every block has passed, and none is in progress.
    public let isOver: Bool
    /// Whether the day is still to come: no block has started.
    public let isAhead: Bool
    /// The blocks just before bedtime set aside to get ready for sleep.
    public let windDownBlocks: Int

    /// 30 minutes.
    public static let standardWindDownBlocks = 6

    public init(schedule: Schedule, nowMinute: Int, windDownBlocks: Int = standardWindDownBlocks) {
        self.schedule = schedule
        self.nowMinute = nowMinute
        isOver = false
        isAhead = false
        self.windDownBlocks = windDownBlocks
    }

    /// A day still to come.
    public init(aheadWith schedule: Schedule, windDownBlocks: Int = standardWindDownBlocks) {
        self.schedule = schedule
        nowMinute = schedule.wakeMinute - Schedule.blockMinutes
        isOver = false
        isAhead = true
        self.windDownBlocks = windDownBlocks
    }

    /// A past day, which ran to bedtime or, when blocks after it are logged, to the end of the last of them.
    public init(schedule: Schedule, endedAfter blocks: Int, windDownBlocks: Int = standardWindDownBlocks) {
        self.schedule = schedule
        nowMinute = schedule.wakeMinute + max(blocks, schedule.awakeBlocks) * Schedule.blockMinutes
        isOver = true
        isAhead = false
        self.windDownBlocks = windDownBlocks
    }

    /// The block `nowMinute` falls in, counted from wake time; nil before waking.
    private var reachedIndex: Int? {
        nowMinute >= schedule.wakeMinute ? (nowMinute - schedule.wakeMinute) / Schedule.blockMinutes : nil
    }

    /// The block in progress, counted from wake time; nil before waking and on a day that's over.
    public var currentIndex: Int? { isOver ? nil : reachedIndex }

    /// Blocks that have fully passed since waking, including any past bedtime.
    public var blocksUsed: Int { reachedIndex ?? 0 }

    /// Blocks started after bedtime, including the one in progress.
    public var overtimeBlocks: Int {
        max(0, (reachedIndex ?? 0) - schedule.awakeBlocks + (isOver ? 0 : 1))
    }

    /// Blocks left before bedtime, counting the one in progress. Goes from 1 straight to -1 at bedtime,
    /// so a negative number is always the count of blocks taken from sleep.
    public var blocksLeft: Int {
        guard let index = reachedIndex else { return schedule.awakeBlocks }
        return index < schedule.awakeBlocks ? schedule.awakeBlocks - index : -overtimeBlocks
    }

    /// Calm on a day that's over or still to come: it's too late, or too soon, for it to matter.
    public var mood: Mood {
        isOver || isAhead ? .calm : Mood(blocksLeft: blocksLeft, windDownBlocks: windDownBlocks)
    }

    /// Blocks the grid shows: the waking day plus any overtime already started.
    public var visibleBlocks: Int { schedule.awakeBlocks + overtimeBlocks }
}
