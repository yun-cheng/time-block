import Foundation

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
    /// This track's starred categories, in the order of `categories` (by group, from `AppSettings`): the palette.
    public let favorites: [BlockCategory]
    public let grid: GridMarks
    /// The day it shows (see `Schedule.dayID`), when known.
    public let day: String?
    /// The stretches timers ran on the day, those running up to now.
    public let sessions: [TimerSession]

    /// Only logs whose category belongs to `track` are drawn. `favorites` are category ids; without them
    /// every category is a favorite.
    public init(
        status: DayStatus, logs: [BlockLog], categories: [BlockCategory], favorites: [String]? = nil,
        track: Track = .activity, grid: GridMarks = .standard, day: String? = nil, sessions: [TimerSession] = []
    ) {
        let byID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.status = status
        self.track = track
        self.grid = grid
        self.day = day
        self.sessions = sessions
        cells = DayGrid.cells(status: status, logs: logs.filter { byID[$0.categoryID]?.track == track })
        self.categories = byID
        let trackCategories = categories.filter { $0.track == track && !$0.isRetired }
        self.trackCategories = trackCategories
        self.favorites = favorites.map { ids in trackCategories.filter { ids.contains($0.id) } } ?? trackCategories
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

    /// Past waking blocks summed up by group (or by category in tracks without groups), most first, and of those as
    /// many, the one the day had first. A block holding several activities counts in full for each of their groups,
    /// so the totals can add up to more than the day. Blocks past bedtime are counted apart, in `pastOvertimeCount`.
    public var legendTotals: [LegendItem] {
        var items: [LegendItem] = []
        var positions: [String: Int] = [:]
        for cell in cells where cell.phase == .past && !cell.isOvertime {
            var counted = Set<String>()
            for category in cell.categoryIDs.compactMap({ categories[$0] }) {
                let key = category.group?.id ?? category.id
                guard counted.insert(key).inserted else { continue }
                if let position = positions[key] {
                    let item = items[position]
                    items[position] = LegendItem(id: key, name: item.name, color: item.color, blocks: item.blocks + 1)
                } else {
                    positions[key] = items.count
                    items.append(LegendItem(
                        id: key, name: category.group?.name ?? category.name,
                        color: category.group?.color ?? category.color, blocks: 1))
                }
            }
        }
        // A stable sort, so ties keep the day's order rather than swapping from one drawing to the next.
        return items.enumerated()
            .sorted { $0.element.blocks != $1.element.blocks ? $0.element.blocks > $1.element.blocks : $0.offset < $1.offset }
            .map(\.element)
    }

    /// The unbroken run of blocks around `index` holding the same activities and notes. Unlogged blocks run together
    /// too, but a gap that has already happened stays apart from empty time still to come, from winding down and from
    /// overtime.
    public func run(around index: Int) -> Range<Int> {
        guard cells.indices.contains(index) else { return index..<(index + 1) }
        let cell = cells[index]
        func sameKind(_ other: BlockCell) -> Bool {
            guard other.categoryIDs == cell.categoryIDs, other.layers.map(\.note) == cell.layers.map(\.note) else {
                return false
            }
            return cell.categoryID != nil
                || ((other.phase == .future) == (cell.phase == .future) && other.isOvertime == cell.isOvertime
                    && other.isWindDown == cell.isWindDown)
        }
        var start = index
        var end = index + 1
        while start > 0, sameKind(cells[start - 1]) { start -= 1 }
        while end < cells.count, sameKind(cells[end]) { end += 1 }
        return start..<end
    }

    /// The unbroken run of blocks around `index` holding `categoryID` with the same note on it: one layer of what they
    /// hold, whatever else is stacked with it.
    public func layerRun(around index: Int, of categoryID: String) -> Range<Int> {
        guard cells.indices.contains(index), let layer = cells[index].layer(categoryID) else { return index..<(index + 1) }
        let isSame = { (cell: BlockCell) in cell.layer(categoryID)?.note == layer.note && cell.layer(categoryID) != nil }
        var start = index
        var end = index + 1
        while start > 0, isSame(cells[start - 1]) { start -= 1 }
        while end < cells.count, isSame(cells[end]) { end += 1 }
        return start..<end
    }

    /// What pointing at or clicking block `index` picks out. A logged block gives the run of its activity (`card`, one
    /// card of a stack, or else the one on top) through every block holding it, stacked with others or not; that's
    /// the activity alone when others share some of those blocks, so what's done to it leaves them be. An unlogged
    /// block gives its gap.
    public func target(at index: Int, card: String? = nil) -> (range: Range<Int>, layer: String?) {
        guard cells.indices.contains(index), let categoryID = card ?? cells[index].categoryID else {
            return (run(around: index), nil)
        }
        let range = layerRun(around: index, of: categoryID)
        return (range, cells[range].contains { $0.layers.count > 1 } ? categoryID : nil)
    }

    /// What right-clicking block `index` (on `card`, one card of a stack) would clear: the whole `selection`, with the
    /// activity picked out of it, when the block is in it, or else what clicking it picks out. Nil when none of
    /// those blocks hold it, so there's nothing to clear.
    public func clearable(
        at index: Int, selection: Range<Int>? = nil, selectedLayer: String? = nil, card: String? = nil
    ) -> (range: Range<Int>, layer: String?)? {
        guard cells.indices.contains(index) else { return nil }
        let target: (range: Range<Int>, layer: String?) =
            selection.flatMap { $0.contains(index) ? ($0, selectedLayer) : nil } ?? self.target(at: index, card: card)
        let cells = cells[target.range.clamped(to: cells.indices)]
        let holds = target.layer.map { layer in cells.contains { $0.layer(layer) != nil } } ?? cells.contains { $0.categoryID != nil }
        return holds ? target : nil
    }

    /// The stretches timers ran of any of `categoryIDs` in blocks of `range`, earliest first.
    public func sessions(of categoryIDs: [String], in range: Range<Int>, calendar: Calendar = .current) -> [TimerSession] {
        guard let day else { return [] }
        return sessions
            .filter { categoryIDs.contains($0.categoryID) }
            .filter { $0.blocks(on: day, schedule: status.schedule, calendar: calendar).overlaps(range) }
            .sorted { $0.start < $1.start }
    }

    /// Whether any block in `range` is logged.
    public func isLogged(anyOf range: Range<Int>) -> Bool {
        cells[range.clamped(to: cells.indices)].contains { $0.categoryID != nil }
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

    /// The longest unbroken run of past blocks holding one category, such as the longest stretch of sitting.
    public func longestRun(of categoryID: String) -> Int {
        var longest = 0
        var run = 0
        for cell in cells where cell.phase == .past {
            run = cell.categoryIDs.contains(categoryID) ? run + 1 : 0
            longest = max(longest, run)
        }
        return longest
    }
}
