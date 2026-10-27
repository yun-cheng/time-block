package dev.timeblock.core

import java.time.ZoneId

/** One line of a day summary, such as "Work 7h 50m" or "Sitting 9h 10m". */
data class LegendItem(val id: String, val name: String, val color: RGB, val blocks: Int)

/** What pointing at or clicking blocks picks out: a run, and the one activity of it, or null for all they hold. */
data class Target(val range: Span, val layer: String?)

/** Everything a view needs to draw one moment of a day in one track. */
class DaySnapshot(
    val status: DayStatus,
    logs: List<BlockLog>,
    categories: List<BlockCategory>,
    /** Category ids; without them every category is a favorite. */
    favorites: List<String>? = null,
    val track: Track = Track.ACTIVITY,
    val grid: GridMarks = GridMarks.standard,
    /** The day it shows (see [Schedule.dayID]), when known. */
    val day: String? = null,
    /** The stretches timers ran on the day, those running up to now. */
    val sessions: List<TimerSession> = emptyList(),
) {
    val categories: Map<String, BlockCategory> = buildMap { for (c in categories) putIfAbsent(c.id, c) }

    /** Only logs whose category belongs to [track] are drawn. */
    val cells: List<BlockCell> = DayGrid.cells(status, logs.filter { this.categories[it.categoryID]?.track == track })

    /** Everything this track's blocks can be logged as now (retired activities aside), for search. */
    val trackCategories: List<BlockCategory> = categories.filter { it.track == track && !it.isRetired }

    /** This track's starred categories, in the order of [categories] (by group, from [AppSettings]): the palette. */
    val favorites: List<BlockCategory> =
        favorites?.let { ids -> trackCategories.filter { it.id in ids } } ?: trackCategories

    val mood: Mood get() = status.mood

    val loggedCount: Int get() = cells.count { it.phase == BlockCell.Phase.PAST && it.categoryID != null }

    val currentCell: BlockCell? get() = status.currentIndex?.let { cells.getOrNull(it) }

    val currentCategory: BlockCategory? get() = currentCell?.categoryID?.let { categories[it] }

    /**
     * Past waking blocks summed up by group (or by category in tracks without groups), most first, and of those as
     * many, the one the day had first. A block holding several activities counts in full for each of their groups, so
     * the totals can add up to more than the day. Blocks past bedtime are counted apart, in [pastOvertimeCount].
     */
    val legendTotals: List<LegendItem>
        get() {
            val items = mutableListOf<LegendItem>()
            val positions = HashMap<String, Int>()
            for (cell in cells.filter { it.phase == BlockCell.Phase.PAST && !it.isOvertime }) {
                val counted = HashSet<String>()
                for (category in cell.categoryIDs.mapNotNull { categories[it] }) {
                    val key = category.group?.id ?: category.id
                    if (!counted.add(key)) continue
                    val position = positions[key]
                    if (position != null) {
                        items[position] = items[position].copy(blocks = items[position].blocks + 1)
                    } else {
                        positions[key] = items.size
                        items += LegendItem(
                            key, category.group?.name ?: category.name, category.group?.color ?: category.color, 1)
                    }
                }
            }
            // A stable sort, so ties keep the day's order rather than swapping from one drawing to the next.
            return items.sortedByDescending { it.blocks }
        }

    /**
     * The unbroken run of blocks around [index] holding the same activities and notes. Unlogged blocks run together
     * too, but a gap that has already happened stays apart from empty time still to come, from winding down and from
     * overtime.
     */
    fun run(around: Int): Span {
        val cell = cells.getOrNull(around) ?: return Span(around, around + 1)
        fun sameKind(other: BlockCell): Boolean {
            if (other.categoryIDs != cell.categoryIDs || other.layers.map { it.note } != cell.layers.map { it.note }) {
                return false
            }
            return cell.categoryID != null ||
                ((other.phase == BlockCell.Phase.FUTURE) == (cell.phase == BlockCell.Phase.FUTURE) &&
                    other.isOvertime == cell.isOvertime && other.isWindDown == cell.isWindDown)
        }
        var start = around
        var end = around + 1
        while (start > 0 && sameKind(cells[start - 1])) start -= 1
        while (end < cells.size && sameKind(cells[end])) end += 1
        return Span(start, end)
    }

    /** The unbroken run of blocks around [around] holding [categoryID] with the same note on it: one layer of what
     *  they hold, whatever else is stacked with it. */
    fun layerRun(around: Int, categoryID: String): Span {
        val layer = cells.getOrNull(around)?.layer(categoryID) ?: return Span(around, around + 1)
        val isSame = { cell: BlockCell -> cell.layer(categoryID)?.let { it.note == layer.note } == true }
        var start = around
        var end = around + 1
        while (start > 0 && isSame(cells[start - 1])) start -= 1
        while (end < cells.size && isSame(cells[end])) end += 1
        return Span(start, end)
    }

    /**
     * What pointing at or clicking block [index] picks out. A logged block gives the run of its activity ([card], one
     * card of a stack, or else the one on top) through every block holding it, stacked with others or not; that's the
     * activity alone when others share some of those blocks, so what's done to it leaves them be. An unlogged block
     * gives its gap.
     */
    fun target(index: Int, card: String? = null): Target {
        val categoryID = card ?: cells.getOrNull(index)?.categoryID
        if (index !in cells.indices || categoryID == null) return Target(run(index), null)
        val range = layerRun(index, categoryID)
        return Target(range, if (range.any { cells[it].layers.size > 1 }) categoryID else null)
    }

    /**
     * What clearing block [index] (on [card], one card of a stack) would clear: the whole [selection], with the
     * activity picked out of it, when the block is in it, or else what clicking it picks out. Null when none of those
     * blocks hold it, so there's nothing to clear.
     */
    fun clearable(index: Int, selection: Span? = null, selectedLayer: String? = null, card: String? = null): Target? {
        if (index !in cells.indices) return null
        val target = selection?.takeIf { index in it }?.let { Target(it, selectedLayer) } ?: target(index, card)
        val shown = target.range.clamped(Span(0, cells.size)).map { cells[it] }
        val holds = if (target.layer != null) {
            shown.any { it.layer(target.layer) != null }
        } else {
            shown.any { it.categoryID != null }
        }
        return if (holds) target else null
    }

    /** The stretches timers ran of any of [categoryIDs] in blocks of [range], earliest first. */
    fun sessions(categoryIDs: List<String>, range: Span, zone: ZoneId = ZoneId.systemDefault()): List<TimerSession> {
        val day = day ?: return emptyList()
        return sessions
            .filter { it.categoryID in categoryIDs && it.blocks(day, status.schedule, zone).overlaps(range) }
            .sortedBy { it.start }
    }

    /** Whether any block in [range] is logged. */
    fun isLogged(anyOf: Span): Boolean = anyOf.clamped(Span(0, cells.size)).any { cells[it].categoryID != null }

    /** The unlogged blocks right before [index], back to the last logged block or wake time. */
    fun unloggedRun(before: Int): Span {
        var start = minOf(before, cells.size)
        while (start > 0 && cells[start - 1].categoryID == null) start -= 1
        return Span(start, minOf(before, cells.size))
    }

    val unloggedCount: Int
        get() = cells.count { it.phase == BlockCell.Phase.PAST && !it.isOvertime && it.categoryID == null }

    val pastOvertimeCount: Int get() = cells.count { it.phase == BlockCell.Phase.PAST && it.isOvertime }

    /** Longest unbroken sit so far, the Body view's headline number; null in other views. */
    val longestSit: Int? get() = if (track == Track.BODY) longestRun("sitting") else null

    /** The longest unbroken run of past blocks holding one category, such as the longest stretch of sitting. */
    fun longestRun(categoryID: String): Int {
        var longest = 0
        var run = 0
        for (cell in cells.filter { it.phase == BlockCell.Phase.PAST }) {
            run = if (categoryID in cell.categoryIDs) run + 1 else 0
            longest = maxOf(longest, run)
        }
        return longest
    }
}
