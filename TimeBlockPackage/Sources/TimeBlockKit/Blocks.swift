import Foundation

/// What kind of time a block was. Each group owns a hue, so a day reads as a story at a glance:
/// blue focus, orange fuel, green body, pink people, teal in transit, yellow recharge, and dull plum
/// for time that drifted away. Bright means intentional; muted means it just happened.
public enum CategoryGroup: String, CaseIterable, Hashable, Sendable {
    case focus, fuel, body, people, transit, recharge, drift

    public var name: String {
        switch self {
        case .focus: "Focus"
        case .fuel: "Fuel"
        case .body: "Body"
        case .people: "People"
        case .transit: "Transit"
        case .recharge: "Recharge"
        case .drift: "Drift"
        }
    }

    public var color: RGB {
        switch self {
        case .focus: RGB(hex: 0x2F6BFF)
        case .fuel: RGB(hex: 0xFF8A3D)
        case .body: RGB(hex: 0x22C55E)
        case .people: RGB(hex: 0xF0508C)
        case .transit: RGB(hex: 0x14B8A6)
        case .recharge: RGB(hex: 0xFACC15)
        case .drift: RGB(hex: 0x8E6A9E)
        }
    }
}

/// One way of looking at the day. Each block can hold one log per track, so 10:00 can be Work in
/// Activity and Standing in Body at the same time. The app shows one track at a time.
public enum Track: String, CaseIterable, Codable, Hashable, Sendable {
    /// What you were doing.
    case activity
    /// What your body was doing: lying, sitting, standing, walking, exercising.
    case body

    public var name: String {
        switch self {
        case .activity: "Activity"
        case .body: "Body"
        }
    }

    /// SF Symbol name.
    public var symbol: String {
        switch self {
        case .activity: "square.grid.3x3.fill"
        case .body: "figure.walk"
        }
    }
}

public struct BlockCategory: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public let track: Track
    /// Activity categories belong to a group, which sets their hue and how time is summed up.
    /// Categories in other tracks have none and are summed up one by one.
    public var group: CategoryGroup?
    public var color: RGB
    /// SF Symbol name.
    public var symbol: String

    /// An Activity category; `color` is a shade within the group's hue and defaults to the group color.
    public init(id: String, name: String, group: CategoryGroup, color: RGB? = nil, symbol: String) {
        self.id = id
        self.name = name
        track = .activity
        self.group = group
        self.color = color ?? group.color
        self.symbol = symbol
    }

    public init(id: String, name: String, track: Track, color: RGB, symbol: String) {
        self.id = id
        self.name = name
        self.track = track
        group = nil
        self.color = color
        self.symbol = symbol
    }
}

extension BlockCategory {
    /// The built-in categories, in the order the palette shows them.
    public static let defaults: [BlockCategory] = [
        BlockCategory(id: "work", name: "Work", group: .focus, symbol: "laptopcomputer"),
        BlockCategory(id: "meeting", name: "Meeting", group: .focus, color: RGB(hex: 0x7FA6FF), symbol: "person.2.fill"),
        BlockCategory(id: "study", name: "Study", group: .focus, color: RGB(hex: 0x4A55E8), symbol: "book.fill"),
        BlockCategory(id: "meal", name: "Meal", group: .fuel, symbol: "fork.knife"),
        BlockCategory(id: "coffee", name: "Coffee", group: .fuel, color: RGB(hex: 0xC9803F), symbol: "cup.and.saucer.fill"),
        BlockCategory(id: "exercise", name: "Exercise", group: .body, symbol: "figure.run"),
        BlockCategory(id: "outdoor", name: "Outdoor", group: .body, color: RGB(hex: 0x84CC16), symbol: "tree.fill"),
        BlockCategory(id: "social", name: "Social", group: .people, symbol: "bubble.left.and.bubble.right.fill"),
        BlockCategory(id: "family", name: "Family", group: .people, color: RGB(hex: 0xF58BBE), symbol: "house.fill"),
        BlockCategory(id: "commute", name: "Commute", group: .transit, symbol: "tram.fill"),
        BlockCategory(id: "rest", name: "Rest", group: .recharge, symbol: "sofa.fill"),
        BlockCategory(id: "nap", name: "Nap", group: .recharge, color: RGB(hex: 0xE8B931), symbol: "powersleep"),
        BlockCategory(id: "screen", name: "Screen time", group: .drift, symbol: "play.rectangle.fill"),
        BlockCategory(id: "doomscroll", name: "Doomscroll", group: .drift, color: RGB(hex: 0x6E4F7E), symbol: "iphone"),
        // Body runs from cool to warm: the more you move, the warmer the block.
        BlockCategory(id: "lying", name: "Lying", track: .body, color: RGB(hex: 0x5B4FC4), symbol: "bed.double.fill"),
        BlockCategory(id: "sitting", name: "Sitting", track: .body, color: RGB(hex: 0x5C86C9), symbol: "chair.fill"),
        BlockCategory(id: "standing", name: "Standing", track: .body, color: RGB(hex: 0x26B5A5), symbol: "figure.stand"),
        BlockCategory(id: "walking", name: "Walking", track: .body, color: RGB(hex: 0x3DCB5F), symbol: "figure.walk"),
        BlockCategory(id: "exercising", name: "Exercising", track: .body, color: RGB(hex: 0xFF9A1F), symbol: "figure.run"),
    ]
}

/// A run of blocks given to one category.
public struct BlockLog: Identifiable, Codable, Hashable, Sendable {
    public enum Source: String, Codable, Hashable, Sendable {
        case manual
        /// A recurring pre-log such as a meal.
        case template
        case calendar
    }

    public let id: UUID
    public var startIndex: Int
    public var length: Int
    public var categoryID: String
    public var note: String?
    public var source: Source

    public init(
        id: UUID = UUID(), startIndex: Int, length: Int, categoryID: String,
        note: String? = nil, source: Source = .manual
    ) {
        self.id = id
        self.startIndex = startIndex
        self.length = length
        self.categoryID = categoryID
        self.note = note
        self.source = source
    }

    public var range: Range<Int> { startIndex..<(startIndex + length) }
}

/// One block as the UI draws it.
public struct BlockCell: Hashable, Sendable {
    public enum Phase: Hashable, Sendable { case past, current, future }

    public let index: Int
    public let phase: Phase
    public let isOvertime: Bool
    public let categoryID: String?
    public let source: BlockLog.Source?
}

public enum DayGrid {
    /// One cell per block from wake time to bedtime, plus any overtime already started. Later logs win.
    public static func cells(status: DayStatus, logs: [BlockLog]) -> [BlockCell] {
        var logAt: [Int: BlockLog] = [:]
        for log in logs {
            for index in log.range { logAt[index] = log }
        }
        let current = status.currentIndex ?? -1
        return (0..<status.visibleBlocks).map { index in
            let phase: BlockCell.Phase = index < current ? .past : index == current ? .current : .future
            let log = logAt[index]
            return BlockCell(
                index: index, phase: phase, isOvertime: index >= status.schedule.awakeBlocks,
                categoryID: log?.categoryID, source: log?.source)
        }
    }
}
