import Foundation

/// What kind of time an activity is. Each group owns a hue, and every activity in it shares that color,
/// so a day reads as a story at a glance however finely it was logged: blue work, violet learning,
/// green health, pink people, orange running your life, teal transit, yellow leisure, and dull plum
/// for time that drifted away.
public enum CategoryGroup: String, CaseIterable, Codable, Hashable, Sendable {
    case work, learn, health, people, life, transit, leisure, drift

    public var name: String {
        switch self {
        case .work: "Work"
        case .learn: "Learn"
        case .health: "Health"
        case .people: "People"
        case .life: "Life"
        case .transit: "Transit"
        case .leisure: "Leisure"
        case .drift: "Drift"
        }
    }

    public var color: RGB {
        switch self {
        case .work: RGB(hex: 0x2F6BFF)
        case .learn: RGB(hex: 0xB45CF0)
        case .health: RGB(hex: 0x22C55E)
        case .people: RGB(hex: 0xF0508C)
        case .life: RGB(hex: 0xFF8A3D)
        case .transit: RGB(hex: 0x14B8A6)
        case .leisure: RGB(hex: 0xFACC15)
        case .drift: RGB(hex: 0x8E6A9E)
        }
    }

    /// Groups saved before they were renamed.
    private static let legacy: [String: CategoryGroup] = [
        "focus": .work, "fuel": .life, "body": .health, "recharge": .leisure,
    ]

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CategoryGroup(rawValue: raw) ?? Self.legacy[raw] ?? .life
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

/// Something a block can be logged as: in Activity, a detailed activity such as Lunch or Email; in Body,
/// a posture such as Sitting.
public struct BlockCategory: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var name: String
    public let track: Track
    /// Activities belong to a group, which sets their color and how time is summed up.
    /// Categories in other tracks have none and are summed up one by one.
    public var group: CategoryGroup? {
        didSet { if let group { color = group.color } }
    }
    public var color: RGB
    /// SF Symbol name.
    public var symbol: String
    /// Other words search should find it by, such as "meal" for Lunch.
    public var keywords: [String]

    /// An Activity, in its group's color.
    public init(id: String, name: String, group: CategoryGroup, symbol: String, keywords: [String] = []) {
        self.id = id
        self.name = name
        track = .activity
        self.group = group
        color = group.color
        self.symbol = symbol
        self.keywords = keywords
    }

    public init(id: String, name: String, track: Track, color: RGB, symbol: String, keywords: [String] = []) {
        self.id = id
        self.name = name
        self.track = track
        group = nil
        self.color = color
        self.symbol = symbol
        self.keywords = keywords
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        track = try container.decode(Track.self, forKey: .track)
        group = try container.decodeIfPresent(CategoryGroup.self, forKey: .group)
        // Activities used to pick a shade; they now all take their group's color.
        color = try group?.color ?? container.decode(RGB.self, forKey: .color)
        symbol = try container.decode(String.self, forKey: .symbol)
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
    }

    /// An activity the user adds, ready to be named.
    public static func new(in track: Track, name: String = "New activity") -> BlockCategory {
        let id = "custom-\(UUID().uuidString)"
        return switch track {
        case .activity: BlockCategory(id: id, name: name, group: .life, symbol: "star.fill")
        case .body: BlockCategory(id: id, name: name, track: track, color: RGB(hex: 0x8A8F98), symbol: "star.fill")
        }
    }
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
    public let note: String?
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
                categoryID: log?.categoryID, source: log?.source, note: log?.note)
        }
    }
}
