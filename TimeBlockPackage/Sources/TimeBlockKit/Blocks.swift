import Foundation

/// What kind of time an activity is. Each group owns a hue, and every activity in it shares that color,
/// so a day reads as a story at a glance however finely it was logged: blue work, violet learning,
/// green health, pink people, orange running your life, teal transit, yellow leisure, and dull plum
/// for time that drifted away.
/// Groups you add pick their own name and color.
public struct CategoryGroup: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var color: RGB

    public init(id: String, name: String, color: RGB) {
        self.id = id
        self.name = name
        self.color = color
    }

    public static let work = CategoryGroup(id: "work", name: "Work", color: RGB(hex: 0x2F6BFF))
    public static let learn = CategoryGroup(id: "learn", name: "Learn", color: RGB(hex: 0xB45CF0))
    public static let health = CategoryGroup(id: "health", name: "Health", color: RGB(hex: 0x22C55E))
    public static let people = CategoryGroup(id: "people", name: "People", color: RGB(hex: 0xF0508C))
    public static let life = CategoryGroup(id: "life", name: "Life", color: RGB(hex: 0xFF8A3D))
    public static let transit = CategoryGroup(id: "transit", name: "Transit", color: RGB(hex: 0x14B8A6))
    public static let leisure = CategoryGroup(id: "leisure", name: "Leisure", color: RGB(hex: 0xFACC15))
    public static let drift = CategoryGroup(id: "drift", name: "Drift", color: RGB(hex: 0x8E6A9E))

    /// The groups every library starts with, in order. Your own come after them.
    public static let builtIn: [CategoryGroup] = [work, learn, health, people, life, transit, leisure, drift]

    public var isBuiltIn: Bool { Self.builtIn.contains { $0.id == id } }

    /// The built-in group with `id`, or with the id it had before groups were renamed.
    public static func builtIn(id: String) -> CategoryGroup? {
        let id = legacy[id] ?? id
        return builtIn.first { $0.id == id }
    }

    private static let legacy = ["focus": "work", "fuel": "life", "body": "health", "recharge": "leisure"]

    /// Colors for your own groups, picked in turn, away from the built-in hues and from overtime red.
    public static let ownColors: [RGB] = [0x8B95A7, 0xA0673A, 0x84CC16, 0x38BDF8, 0xD946EF, 0x6366F1].map(RGB.init(hex:))

    /// A group the user adds, ready to be named.
    public static func new(name: String = "New group", color: RGB) -> CategoryGroup {
        CategoryGroup(id: "group-\(UUID().uuidString)", name: name, color: color)
    }
}

/// One way of looking at the day. Each track is logged apart, so 10:00 can be Work in Activity and Standing
/// in Body at the same time. The app shows one track at a time.
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
    /// Whether you removed it (see `AppSettings.removedCategories`). Not saved with it: settings keep the list.
    public var isRemoved = false

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
        // Only the group's id is saved. One of your own stands in as a placeholder until `AppSettings` finds it.
        group = try container.decodeIfPresent(String.self, forKey: .group).map {
            CategoryGroup.builtIn(id: $0) ?? CategoryGroup(id: $0, name: "", color: CategoryGroup.life.color)
        }
        // Activities used to pick a shade; they now all take their group's color.
        color = try group?.color ?? container.decode(RGB.self, forKey: .color)
        symbol = try container.decode(String.self, forKey: .symbol)
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, track, group, color, symbol, keywords
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(track, forKey: .track)
        try container.encodeIfPresent(group?.id, forKey: .group)
        try container.encode(color, forKey: .color)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(keywords, forKey: .keywords)
    }

    /// An activity the user adds, ready to be named.
    public static func new(in track: Track, group: CategoryGroup = .life, name: String = "New activity") -> BlockCategory {
        let id = "custom-\(UUID().uuidString)"
        return switch track {
        case .activity: BlockCategory(id: id, name: name, group: group, symbol: "star.fill")
        case .body: BlockCategory(id: id, name: name, track: track, color: RGB(hex: 0x8A8F98), symbol: "star.fill")
        }
    }
}

/// A run of blocks given to one category. Logs of one track can overlap: a block can hold several activities at
/// once (see `DayGrid.cells` for which is on top).
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

    /// One of the activities a block holds at once.
    public struct Layer: Hashable, Sendable {
        public let categoryID: String
        public let source: BlockLog.Source
        public let note: String?

        public init(categoryID: String, source: BlockLog.Source = .manual, note: String? = nil) {
            self.categoryID = categoryID
            self.source = source
            self.note = note
        }
    }

    public let index: Int
    public let phase: Phase
    public let isOvertime: Bool
    /// Whether it's one of the blocks before bedtime set aside to wind down.
    public let isWindDown: Bool
    /// What it holds, bottom first (see `DayGrid.cells` for the order). Empty when it's unlogged.
    public let layers: [Layer]

    public init(index: Int, phase: Phase, isOvertime: Bool, isWindDown: Bool, layers: [Layer] = []) {
        self.index = index
        self.phase = phase
        self.isOvertime = isOvertime
        self.isWindDown = isWindDown
        self.layers = layers
    }

    /// The activity on top.
    public var categoryID: String? { layers.last?.categoryID }
    public var source: BlockLog.Source? { layers.last?.source }
    public var note: String? { layers.last?.note }

    /// Every activity it holds, bottom first.
    public var categoryIDs: [String] { layers.map(\.categoryID) }

    /// The same block holding `layers`: what an edit would make it.
    public func holding(_ layers: [Layer]) -> BlockCell {
        BlockCell(index: index, phase: phase, isOvertime: isOvertime, isWindDown: isWindDown, layers: layers)
    }

    /// The same block logged by hand as `categoryID` alone, or emptied with nil.
    public func logged(as categoryID: String?) -> BlockCell {
        holding(categoryID.map { [Layer(categoryID: $0)] } ?? [])
    }
}

public enum DayGrid {
    /// One cell per block from wake time to bedtime, plus any overtime already started.
    ///
    /// Logs that overlap are layers, and what breaks into something else goes on top: in each block, the activity
    /// whose unbroken stretch is shortest, so a trip to the toilet sits on a morning of work, a podcast on a commute
    /// and dinner on an evening of TV. Of stretches as long, the one starting later broke in; of those, the one logged
    /// last is on top. A stretch is measured whole, so two activities keep one order in every block they share.
    public static func cells(status: DayStatus, logs: [BlockLog]) -> [BlockCell] {
        var layersAt: [Int: [(layer: BlockCell.Layer, order: Int)]] = [:]
        var held: [String: Set<Int>] = [:]
        for (order, log) in logs.enumerated() {
            let layer = BlockCell.Layer(categoryID: log.categoryID, source: log.source, note: log.note)
            for index in log.range { layersAt[index, default: []].append((layer, order)) }
            held[log.categoryID, default: []].formUnion(log.range)
        }
        /// The unbroken stretch of `categoryID` that block `index` is in.
        func stretch(of categoryID: String, at index: Int) -> Range<Int> {
            let blocks = held[categoryID] ?? []
            var start = index
            var end = index + 1
            while blocks.contains(start - 1) { start -= 1 }
            while blocks.contains(end) { end += 1 }
            return start..<end
        }
        let current = status.currentIndex ?? (status.isOver ? status.visibleBlocks : -1)
        let windDown = status.windDownRange
        return (0..<status.visibleBlocks).map { index in
            let phase: BlockCell.Phase = index < current ? .past : index == current ? .current : .future
            let layers = (layersAt[index] ?? []).sorted { lower, upper in
                let a = stretch(of: lower.layer.categoryID, at: index)
                let b = stretch(of: upper.layer.categoryID, at: index)
                if a.count != b.count { return a.count > b.count }
                if a.lowerBound != b.lowerBound { return a.lowerBound < b.lowerBound }
                return lower.order < upper.order
            }
            return BlockCell(
                index: index, phase: phase, isOvertime: index >= status.schedule.awakeBlocks,
                isWindDown: windDown.contains(index), layers: layers.map(\.layer))
        }
    }
}
