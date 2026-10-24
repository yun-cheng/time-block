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
    /// Everything this track's blocks can be logged as now (retired activities aside), for search.
    public let trackCategories: [BlockCategory]
    /// This track's starred categories, in palette order.
    public let favorites: [BlockCategory]

    /// Only logs whose category belongs to `track` are drawn. `favorites` are category ids; without them
    /// every category is a favorite.
    public init(
        status: DayStatus, logs: [BlockLog], categories: [BlockCategory], favorites: [String]? = nil,
        track: Track = .activity
    ) {
        let byID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.status = status
        self.track = track
        cells = DayGrid.cells(status: status, logs: logs.filter { byID[$0.categoryID]?.track == track })
        self.categories = byID
        trackCategories = categories.filter { $0.track == track && !$0.isRetired }
        self.favorites = favorites.map {
            $0.compactMap { byID[$0] }.filter { $0.track == track && !$0.isRetired }
        } ?? trackCategories
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

    /// The unbroken run of blocks around `index` holding the same category and note. Unlogged blocks run together
    /// too, but a gap that has already happened stays apart from empty time still to come and from overtime.
    public func run(around index: Int) -> Range<Int> {
        guard cells.indices.contains(index) else { return index..<(index + 1) }
        let cell = cells[index]
        func sameKind(_ other: BlockCell) -> Bool {
            guard other.categoryID == cell.categoryID, other.note == cell.note else { return false }
            return cell.categoryID != nil
                || ((other.phase == .future) == (cell.phase == .future) && other.isOvertime == cell.isOvertime)
        }
        var start = index
        var end = index + 1
        while start > 0, sameKind(cells[start - 1]) { start -= 1 }
        while end < cells.count, sameKind(cells[end]) { end += 1 }
        return start..<end
    }

    /// The unlogged blocks right before `index`, back to the last logged block or wake time.
    public func unloggedRun(before index: Int) -> Range<Int> {
        var start = min(index, cells.count)
        while start > 0, cells[start - 1].categoryID == nil { start -= 1 }
        return start..<min(index, cells.count)
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
