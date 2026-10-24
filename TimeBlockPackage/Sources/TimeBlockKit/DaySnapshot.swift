/// One line of a day summary, such as "Focus 7h 50m" or "Sitting 9h 10m".
public struct LegendItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let color: RGB
    public let blocks: Int
}

/// Everything a view needs to draw one moment of a day in one track.
public struct DaySnapshot: Sendable {
    public let status: DayStatus
    public let track: Track
    public let cells: [BlockCell]
    public let categories: [String: BlockCategory]

    /// Only logs whose category belongs to `track` are drawn.
    public init(status: DayStatus, logs: [BlockLog], categories: [BlockCategory], track: Track = .activity) {
        let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        self.status = status
        self.track = track
        cells = DayGrid.cells(status: status, logs: logs.filter { byID[$0.categoryID]?.track == track })
        self.categories = byID
    }

    public var mood: Mood { status.mood }

    public var loggedCount: Int {
        cells.lazy.filter { $0.phase == .past && $0.categoryID != nil }.count
    }

    public var currentCell: BlockCell? {
        status.currentIndex.flatMap { cells.indices.contains($0) ? cells[$0] : nil }
    }

    public var currentCategory: BlockCategory? {
        currentCell?.categoryID.flatMap { categories[$0] }
    }

    /// Past waking blocks summed up by group (or by category in tracks without groups), most first.
    /// Blocks past bedtime are counted apart, in `pastOvertimeCount`.
    public var legendTotals: [LegendItem] {
        var counts: [String: (name: String, color: RGB, blocks: Int)] = [:]
        for cell in cells where cell.phase == .past && !cell.isOvertime {
            guard let category = cell.categoryID.flatMap({ categories[$0] }) else { continue }
            let key = category.group?.rawValue ?? category.id
            let name = category.group?.name ?? category.name
            let color = category.group?.color ?? category.color
            counts[key, default: (name, color, 0)].blocks += 1
        }
        return counts
            .map { LegendItem(id: $0.key, name: $0.value.name, color: $0.value.color, blocks: $0.value.blocks) }
            .sorted { $0.blocks > $1.blocks }
    }

    public var unloggedCount: Int {
        cells.lazy.filter { $0.phase == .past && !$0.isOvertime && $0.categoryID == nil }.count
    }

    public var pastOvertimeCount: Int {
        cells.lazy.filter { $0.phase == .past && $0.isOvertime }.count
    }

    /// Longest unbroken sit so far, the Body view's headline number; nil in other views.
    public var longestSit: Int? {
        track == .body ? longestRun(of: "sitting") : nil
    }

    /// The longest unbroken run of past blocks in one category, such as the longest stretch of sitting.
    public func longestRun(of categoryID: String) -> Int {
        var longest = 0
        var run = 0
        for cell in cells where cell.phase == .past {
            run = cell.categoryID == categoryID ? run + 1 : 0
            longest = max(longest, run)
        }
        return longest
    }
}
