import Foundation

/// Time that comes back on given days, such as Lunch at 12:30 on weekdays. Each of those days it's pre-logged in
/// whatever blocks are free then: hollow until the time comes, then logged, unless you paint over it.
public struct Template: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var categoryID: String
    /// What its start is counted from: a clock time, the day's wake time or bedtime, or the end of an activity.
    public var anchor: Anchor
    /// The activity it starts after, when it's anchored to one.
    public var afterCategoryID: String?
    /// Clock minute it starts at (0..<1440), on a block boundary, when it's anchored to the clock. Kept when it's
    /// anchored elsewhere, so going back to a clock time finds it again.
    public var startMinute: Int
    /// Minutes after waking, before bed, or after the activity it follows ends, that it starts at, on a block
    /// boundary.
    public var offset: Int
    /// In blocks.
    public var length: Int
    /// The days it comes back on, as `Calendar` weekdays: 1 is Sunday, 7 Saturday.
    public var weekdays: Set<Int>
    /// Paused templates stay listed but pre-log nothing.
    public var isEnabled: Bool
    /// Whether a notification says when it starts.
    public var notifies: Bool

    public init(
        id: String = "template-\(UUID().uuidString)", categoryID: String, anchor: Anchor = .clock,
        afterCategoryID: String? = nil, startMinute: Int = 12 * 60, offset: Int = 0, length: Int,
        weekdays: Set<Int> = Template.everyDay, isEnabled: Bool = true, notifies: Bool = false
    ) {
        self.id = id
        self.categoryID = categoryID
        self.anchor = anchor
        self.afterCategoryID = afterCategoryID
        self.startMinute = startMinute
        self.offset = offset
        self.length = length
        self.weekdays = weekdays
        self.isEnabled = isEnabled
        self.notifies = notifies
    }

    public static let everyDay: Set<Int> = Set(1...7)
    public static let weekdaysOnly: Set<Int> = Set(2...6)
    public static let weekends: Set<Int> = [1, 7]

    /// The blocks it covers on a day with `schedule`, cut to the waking day. One that starts after an activity needs
    /// `end`, the block that activity ends at that day, and covers none without it.
    public func range(in schedule: Schedule, following end: Int? = nil) -> Range<Int> {
        let start: Int? = switch anchor {
        case .clock: schedule.blockIndex(clockMinute: startMinute)
        case .wake: offset / Schedule.blockMinutes
        case .bed: schedule.awakeBlocks - offset / Schedule.blockMinutes
        case .after: end.map { $0 + offset / Schedule.blockMinutes }
        }
        guard let start else { return 0..<0 }
        let range = start..<(start + length)
        return range.clamped(to: 0..<max(0, schedule.awakeBlocks))
    }

    /// Clock minute it starts at on a day with `schedule`; after an activity that ends at block `end`, or, with no
    /// `end`, the one it was last at a clock time.
    public func startMinute(in schedule: Schedule, following end: Int? = nil) -> Int {
        switch anchor {
        case .clock: startMinute
        case .wake: (schedule.wakeMinute + offset) % (24 * 60)
        case .bed: ((schedule.bedMinute - offset) % (24 * 60) + 24 * 60) % (24 * 60)
        case .after:
            end.map { (schedule.wakeMinute + $0 * Schedule.blockMinutes + offset) % (24 * 60) } ?? startMinute
        }
    }

    /// Counts its start from `anchor` instead, and after the activity `afterCategoryID` for `.after`: a clock time
    /// keeps where it starts on a day with `schedule` (where the activity it follows ends at block `end`), after
    /// waking or before bed start at `defaultOffset`, not however far the clock time is from them, and after an
    /// activity starts as it ends.
    public mutating func anchor(
        to anchor: Anchor, after afterCategoryID: String? = nil, in schedule: Schedule, following end: Int? = nil
    ) {
        guard anchor != self.anchor || (anchor == .after && afterCategoryID != self.afterCategoryID) else { return }
        switch anchor {
        case .clock: startMinute = startMinute(in: schedule, following: end)
        case .wake, .bed: offset = Self.defaultOffset
        case .after where self.anchor != .after: offset = 0
        case .after: break
        }
        self.anchor = anchor
        self.afterCategoryID = anchor == .after ? afterCategoryID : nil
    }

    /// What after waking and before bed start at: half an hour.
    public static let defaultOffset = 30

    /// Those that start after an activity, each after any of them that pre-log the activity it follows, so that's
    /// laid out first. Ones that follow each other round in a circle go last, as they come.
    static func inLayingOrder(_ templates: [Template]) -> [Template] {
        var waiting = templates.filter { $0.anchor == .after }
        var ordered: [Template] = []
        while !waiting.isEmpty {
            let ready = waiting.filter { template in
                !waiting.contains { $0.id != template.id && $0.categoryID == template.afterCategoryID }
            }
            let next = ready.isEmpty ? waiting : ready
            ordered += next
            waiting.removeAll { template in next.contains { $0.id == template.id } }
        }
        return ordered
    }

    public enum Anchor: String, Codable, CaseIterable, Sendable {
        /// At a clock time, such as Lunch at 12:30.
        case clock
        /// A while after waking, such as Breakfast 30 minutes after, whenever that is.
        case wake
        /// A while before bed, such as Reading 45 minutes before.
        case bed
        /// A while after an activity ends, such as a Shower 15 minutes after the Gym: each time that day it's logged
        /// or pre-logged, wherever that is.
        case after
    }
}

extension Template {
    /// Templates saved before anchors start at a clock time, and ones saved before notifications don't notify.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        categoryID = try container.decode(String.self, forKey: .categoryID)
        anchor = try container.decodeIfPresent(Anchor.self, forKey: .anchor) ?? .clock
        afterCategoryID = try container.decodeIfPresent(String.self, forKey: .afterCategoryID)
        startMinute = try container.decode(Int.self, forKey: .startMinute)
        offset = try container.decodeIfPresent(Int.self, forKey: .offset) ?? 0
        length = try container.decode(Int.self, forKey: .length)
        weekdays = try container.decode(Set<Int>.self, forKey: .weekdays)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        notifies = try container.decodeIfPresent(Bool.self, forKey: .notifies) ?? false
    }
}

