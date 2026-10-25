import Foundation

/// Time that comes back on given days, such as Lunch at 12:30 on weekdays. Each of those days it's pre-logged in
/// whatever blocks are free then: hollow until the time comes, then logged, unless you paint over it.
public struct Template: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var categoryID: String
    /// Clock minute it starts at (0..<1440), on a block boundary.
    public var startMinute: Int
    /// In blocks.
    public var length: Int
    /// The days it comes back on, as `Calendar` weekdays: 1 is Sunday, 7 Saturday.
    public var weekdays: Set<Int>
    /// Paused templates stay listed but pre-log nothing.
    public var isEnabled: Bool

    public init(
        id: String = "template-\(UUID().uuidString)", categoryID: String, startMinute: Int, length: Int,
        weekdays: Set<Int> = Template.everyDay, isEnabled: Bool = true
    ) {
        self.id = id
        self.categoryID = categoryID
        self.startMinute = startMinute
        self.length = length
        self.weekdays = weekdays
        self.isEnabled = isEnabled
    }

    public static let everyDay: Set<Int> = Set(1...7)
    public static let weekdaysOnly: Set<Int> = Set(2...6)
    public static let weekends: Set<Int> = [1, 7]

    /// The blocks it covers on a day with `schedule`, cut to the waking day.
    public func range(in schedule: Schedule) -> Range<Int> {
        let start = schedule.blockIndex(clockMinute: startMinute)
        let range = start..<(start + length)
        return range.clamped(to: 0..<max(0, schedule.awakeBlocks))
    }
}
