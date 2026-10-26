import Foundation

/// Time that comes back on given days, such as Lunch at 12:30 on weekdays. Each of those days it's pre-logged in
/// whatever blocks are free then: hollow until the time comes, then logged, unless you paint over it.
public struct Template: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var categoryID: String
    /// What its start is counted from: a clock time, or the day's wake time or bedtime.
    public var anchor: Anchor
    /// Clock minute it starts at (0..<1440), on a block boundary, when it's anchored to the clock. Kept when it's
    /// anchored elsewhere, so going back to a clock time finds it again.
    public var startMinute: Int
    /// Minutes after waking, or before bed, that it starts at, on a block boundary.
    public var offset: Int
    /// In blocks.
    public var length: Int
    /// The days it comes back on, as `Calendar` weekdays: 1 is Sunday, 7 Saturday.
    public var weekdays: Set<Int>
    /// Paused templates stay listed but pre-log nothing.
    public var isEnabled: Bool

    public init(
        id: String = "template-\(UUID().uuidString)", categoryID: String, anchor: Anchor = .clock,
        startMinute: Int = 12 * 60, offset: Int = 0, length: Int, weekdays: Set<Int> = Template.everyDay,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.categoryID = categoryID
        self.anchor = anchor
        self.startMinute = startMinute
        self.offset = offset
        self.length = length
        self.weekdays = weekdays
        self.isEnabled = isEnabled
    }

    public static let everyDay: Set<Int> = Set(1...7)
    public static let weekdaysOnly: Set<Int> = Set(2...6)
    public static let weekends: Set<Int> = [1, 7]

    /// The blocks it covers on a day with `schedule`, cut to the waking day.
    public func range(in schedule: Schedule) -> Range<Int> {
        let start = switch anchor {
        case .clock: schedule.blockIndex(clockMinute: startMinute)
        case .wake: offset / Schedule.blockMinutes
        case .bed: schedule.awakeBlocks - offset / Schedule.blockMinutes
        }
        let range = start..<(start + length)
        return range.clamped(to: 0..<max(0, schedule.awakeBlocks))
    }

    /// Clock minute it starts at on a day with `schedule`.
    public func startMinute(in schedule: Schedule) -> Int {
        switch anchor {
        case .clock: startMinute
        case .wake: (schedule.wakeMinute + offset) % (24 * 60)
        case .bed: ((schedule.bedMinute - offset) % (24 * 60) + 24 * 60) % (24 * 60)
        }
    }

    /// Counts its start from `anchor` instead: a clock time keeps where it starts on a day with `schedule`, and
    /// after waking or before bed start at `defaultOffset`, not however far the clock time is from them.
    public mutating func anchor(to anchor: Anchor, in schedule: Schedule) {
        guard anchor != self.anchor else { return }
        switch anchor {
        case .clock: startMinute = startMinute(in: schedule)
        case .wake, .bed: offset = Self.defaultOffset
        }
        self.anchor = anchor
    }

    /// What after waking and before bed start at: half an hour.
    public static let defaultOffset = 30

    public enum Anchor: String, Codable, CaseIterable, Sendable {
        /// At a clock time, such as Lunch at 12:30.
        case clock
        /// A while after waking, such as Breakfast 30 minutes after, whenever that is.
        case wake
        /// A while before bed, such as Reading 45 minutes before.
        case bed
    }
}

extension Template {
    /// Templates saved before anchors start at a clock time.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        categoryID = try container.decode(String.self, forKey: .categoryID)
        anchor = try container.decodeIfPresent(Anchor.self, forKey: .anchor) ?? .clock
        startMinute = try container.decode(Int.self, forKey: .startMinute)
        offset = try container.decodeIfPresent(Int.self, forKey: .offset) ?? 0
        length = try container.decode(Int.self, forKey: .length)
        weekdays = try container.decode(Set<Int>.self, forKey: .weekdays)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
    }
}
