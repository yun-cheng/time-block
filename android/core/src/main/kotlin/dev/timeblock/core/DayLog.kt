package dev.timeblock.core

import kotlinx.serialization.Serializable
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.time.Instant
import java.time.ZoneId
import kotlin.math.max

/** One day's logs in every track, as saved on disk. Each change gives a new day rather than changing this one. */
@Serializable
data class DayLog(
    /** See [Schedule.dayID]. */
    val day: String,
    /** The wake time block indexes count from. Logs are moved when the schedule's wake time changes, so a block keeps
     *  its clock time. */
    val wakeMinute: Int,
    /** The day's own schedule, as it was when its logs last changed, so a past day keeps its length when the schedule
     *  changes later. Null for days saved before schedules were kept with them. */
    val schedule: Schedule? = null,
    val logs: List<BlockLog> = emptyList(),
    /** Whether the day's templates have been laid out on it (see [plan]). */
    val isPlanned: Boolean = false,
    /** The stretches timers ran, to the second, in the order they ended (see [record]). */
    val sessions: List<TimerSession> = emptyList(),
) {
    /** The day of the week, as a Swift `Calendar` weekday (1 is Sunday). */
    val weekday: Int? get() = DayID.weekday(day)

    /** The logs with block indexes counted from [schedule]'s wake time. */
    fun logs(schedule: Schedule): List<BlockLog> {
        val shift = (wakeMinute - schedule.wakeMinute) / Schedule.BLOCK_MINUTES
        if (shift == 0) return logs
        return logs.map { it.copy(startIndex = it.startIndex + shift) }
    }

    /** Counts block indexes from [schedule]'s wake time from now on, and keeps it as the day's schedule. */
    fun rebased(schedule: Schedule): DayLog =
        copy(logs = logs(schedule), wakeMinute = schedule.wakeMinute, schedule = schedule)

    /**
     * Gives [range] to a category alone, in place of everything it held, or clears it with null. Only logs in the
     * category's track (or [track], when clearing) change: parts outside [range] are kept, and runs of one category
     * join up. A run that is given another category as a whole keeps its note. With [layer], only that activity is
     * replaced or cleared, and the one replacing it joins the rest.
     */
    fun set(
        range: Span, categoryID: String?, track: Track, schedule: Schedule,
        categories: List<BlockCategory> = BlockCategories.defaults, layer: String? = null,
    ): DayLog {
        if (range.isEmpty) return this
        val day = rebased(schedule)
        val (kept, cut) = split(day.logs, range, track, categories) {
            layer == null || it.categoryID == layer || it.categoryID == categoryID
        }
        val logs = kept.toMutableList()
        if (categoryID != null) {
            val replaced = if (layer != null) cut.filter { it.categoryID == layer } else cut
            val notes = replaced.map { it.note }.toSet()
            val note = if (replaced.all { it.range in range } && notes.size == 1) notes.first() else null
            logs += BlockLog(startIndex = range.lowerBound, length = range.count, categoryID = categoryID, note = note)
        }
        return day.copy(logs = joined(logs))
    }

    /** Whether every block of [range] holds [categoryID], alone or with others. */
    fun holds(categoryID: String, throughout: Span, schedule: Schedule): Boolean {
        val held = logs(schedule).filter { it.categoryID == categoryID }.flatMap { it.range }.toSet()
        return !throughout.isEmpty && throughout.all { it in held }
    }

    /**
     * Takes [categoryID] off [range] when every block of it holds it; otherwise adds it to what the blocks hold, as one
     * more activity at the same time. Nothing else they hold changes.
     */
    fun toggle(
        categoryID: String, range: Span, schedule: Schedule, categories: List<BlockCategory> = BlockCategories.defaults,
    ): DayLog {
        val track = categories.firstOrNull { it.id == categoryID }?.track
        if (range.isEmpty || track == null) return this
        val isHeld = holds(categoryID, range, schedule)
        val day = rebased(schedule)
        val logs = split(day.logs, range, track, categories) { it.categoryID == categoryID }.first.toMutableList()
        if (!isHeld) logs += BlockLog(startIndex = range.lowerBound, length = range.count, categoryID = categoryID)
        return day.copy(logs = joined(logs))
    }

    /** Adds [categoryID] to the blocks of [range] that don't hold it yet, alongside what they hold. Blocks holding it
     *  already keep it as it was, note and all. */
    fun add(categoryID: String, range: Span, schedule: Schedule): DayLog {
        if (range.isEmpty) return this
        val day = rebased(schedule)
        val held = day.logs.filter { it.categoryID == categoryID }.flatMap { it.range }.toSet()
        val added = runs(range) { it !in held }.map {
            BlockLog(startIndex = it.lowerBound, length = it.count, categoryID = categoryID)
        }
        return day.copy(logs = joined(day.logs + added))
    }

    /** Logs a stretch a timer ran: its activity is added to every block of the day it ran in, any part of it, and its
     *  exact times are kept, to show over those blocks. */
    fun record(session: TimerSession, schedule: Schedule, zone: ZoneId = ZoneId.systemDefault()): DayLog {
        val range = session.blocks(day, schedule, zone)
        if (range.isEmpty) return this
        val added = add(session.categoryID, range, schedule)
        return added.copy(sessions = added.sessions + session)
    }

    /**
     * Writes [note] on the logged blocks of [range] in [track], or takes their note off with null or blank. Logs
     * reaching past [range] are split, so the note covers exactly those blocks. With [layer], only that activity takes
     * it.
     */
    fun setNote(
        note: String?, range: Span, track: Track, schedule: Schedule,
        categories: List<BlockCategory> = BlockCategories.defaults, layer: String? = null,
    ): DayLog {
        if (range.isEmpty) return this
        val day = rebased(schedule)
        val trimmed = note?.trim()?.ifEmpty { null }
        val (kept, cut) = split(day.logs, range, track, categories) { layer == null || it.categoryID == layer }
        val noted = cut.map { log ->
            val inside = log.range.clamped(range)
            BlockLog(
                startIndex = inside.lowerBound, length = inside.count, categoryID = log.categoryID, note = trimmed,
                source = log.source, templateID = log.templateID)
        }
        return day.copy(logs = joined(kept + noted))
    }

    /**
     * Moves the ends of the run of one category at [range] in [track] to [newRange]: blocks it takes in are logged as
     * it, overwriting what they held there, and blocks it lets go are cleared. The run keeps its note when it has one.
     * Nothing changes unless [range] is all logged as one category. With [layer], only that activity's run moves its
     * ends, alongside what the blocks it takes in hold.
     */
    fun resize(
        range: Span, newRange: Span, track: Track, schedule: Schedule,
        categories: List<BlockCategory> = BlockCategories.defaults, layer: String? = null,
    ): DayLog {
        if (range.isEmpty || newRange.isEmpty || newRange == range) return this
        val day = rebased(schedule)
        val (kept, cut) = split(day.logs, range, track, categories) { layer == null || it.categoryID == layer }
        val notes = cut.map { it.note }.toSet()
        val categoryID = cut.firstOrNull()?.categoryID ?: return day
        if (!cut.all { it.categoryID == categoryID } || cut.sumOf { it.range.clamped(range).count } != range.count) {
            return day
        }
        val rest = split(kept, newRange, track, categories) { layer == null || it.categoryID == categoryID }.first
        val note = if (notes.size == 1) notes.first() else null
        return day.copy(
            logs = joined(rest + BlockLog(
                startIndex = newRange.lowerBound, length = newRange.count, categoryID = categoryID, note = note)))
    }

    /**
     * Moves what [range] holds in [track] [offset] blocks along, gaps and notes included, so the blocks it lands on end
     * up just like [range] was and the blocks it leaves are cleared. Nothing changes when [range] holds nothing. With
     * [layer], only that activity moves, alongside what the blocks it lands on hold.
     */
    fun move(
        range: Span, offset: Int, track: Track, schedule: Schedule,
        categories: List<BlockCategory> = BlockCategories.defaults, layer: String? = null,
    ): DayLog {
        if (range.isEmpty || offset == 0) return this
        val day = rebased(schedule)
        val isMoved = { log: BlockLog -> layer == null || log.categoryID == layer }
        val (kept, cut) = split(day.logs, range, track, categories, isMoved)
        if (cut.isEmpty()) return day
        val rest = split(kept, range.shifted(offset), track, categories, isMoved).first
        val moved = cut.map { log ->
            val inside = log.range.clamped(range)
            BlockLog(
                startIndex = inside.lowerBound + offset, length = inside.count, categoryID = log.categoryID,
                note = log.note)
        }
        return day.copy(logs = joined(rest + moved))
    }

    /**
     * Pre-logs the templates that come back on this day, from block [from] on, in the blocks still free in their
     * category's track. What templates logged from [from] on before is taken back first, so a changed template moves;
     * blocks before [from] keep what they had. One that starts after an activity is laid out after each time that day
     * it's logged or pre-logged, and not at all when it isn't. Paused templates, and ones for retired activities, log
     * nothing.
     */
    fun plan(
        templates: List<Template>, from: Int = 0, schedule: Schedule,
        categories: List<BlockCategory> = BlockCategories.defaults,
    ): DayLog {
        val day = rebased(schedule)
        var logs = day.logs.mapNotNull { log ->
            when {
                log.source != BlockLog.Source.TEMPLATE || log.range.upperBound <= from -> log
                log.startIndex >= from -> null
                else -> log.copy(length = from - log.startIndex)
            }
        }
        val comingBack = templates.filter(::comesBack)
        for (template in comingBack.filter { it.anchor != Template.Anchor.AFTER }) {
            logs = preLog(logs, template, template.range(schedule), from, categories)
        }
        for (template in Template.inLayingOrder(comingBack)) {
            for (end in ends(logs, template)) {
                logs = preLog(logs, template, template.range(schedule, end), from, categories)
            }
        }
        return day.copy(logs = joined(logs), isPlanned = true)
    }

    /**
     * Moves the templates that start after an activity, from block [from] on, to follow it where it is now that the
     * logs have changed from [before]: logged, moved or cleared. Each time of it that ends where it did keeps what
     * follows it as it is, cleared blocks and all.
     */
    fun follow(
        templates: List<Template>, from: Int, before: DayLog, schedule: Schedule,
        categories: List<BlockCategory> = BlockCategories.defaults,
    ): DayLog {
        val previous = before.rebased(schedule)
        var logs = logs
        var changed = false
        for (template in Template.inLayingOrder(templates.filter(::comesBack))) {
            val ends = ends(logs, template)
            val old = ends(previous.logs, template)
            if (ends == old) continue
            val track = categories.firstOrNull { it.id == template.categoryID }?.track
            if (track != null) {
                for (end in old.filter { it !in ends }) {
                    val range = template.range(schedule, end)
                    if (range.upperBound <= from) continue
                    logs = split(logs, Span(max(from, range.lowerBound), range.upperBound), track, categories) {
                        it.templateID == template.id
                    }.first
                }
            }
            for (end in ends.filter { it !in old }) {
                logs = preLog(logs, template, template.range(schedule, end), from, categories)
            }
            changed = true
        }
        return if (changed) copy(logs = joined(logs)) else this
    }

    /**
     * Where the activity [template] starts after ends each time it's on this day, logged or pre-logged by anything but
     * it, in order; none when it isn't, or [template] doesn't start after one.
     */
    fun ends(template: Template): List<Int> = ends(logs, template)

    /** The block after the last one logged in any track, or 0 when nothing is. */
    fun loggedEnd(schedule: Schedule): Int = logs(schedule).maxOfOrNull { it.range.upperBound } ?: 0

    private fun comesBack(template: Template): Boolean =
        template.isEnabled && weekday?.let { it in template.weekdays } == true

    companion object {
        private fun ends(logs: List<BlockLog>, template: Template): List<Int> {
            val id = template.afterCategoryID
            if (template.anchor != Template.Anchor.AFTER || id == null) return emptyList()
            val ranges = logs.filter { it.categoryID == id && it.templateID != template.id }.map { it.range }
                .sortedBy { it.lowerBound }
            val ends = mutableListOf<Int>()
            for (range in ranges) {
                // Touching or overlapping runs of it are one time.
                val last = ends.lastOrNull()
                if (last != null && range.lowerBound <= last) {
                    ends[ends.size - 1] = max(last, range.upperBound)
                } else {
                    ends += range.upperBound
                }
            }
            return ends
        }

        /** [logs] with [template] pre-logged in the blocks of [range] from [from] on that are still free in its
         *  category's track. */
        private fun preLog(
            logs: List<BlockLog>, template: Template, range: Span, from: Int, categories: List<BlockCategory>,
        ): List<BlockLog> {
            val category = categories.firstOrNull { it.id == template.categoryID }
            if (category == null || category.isRetired) return logs
            val trackOf = categories.associateTracks()
            val taken = logs.filter { trackOf[it.categoryID] == category.track }.flatMap { it.range }.toSet()
            return logs + runs(range.clamped(Span(from, max(from, range.upperBound)))) { it !in taken }.map {
                BlockLog(
                    startIndex = it.lowerBound, length = it.count, categoryID = category.id,
                    source = BlockLog.Source.TEMPLATE, templateID = template.id)
            }
        }

        /** The unbroken runs of blocks in [range] that [isFree] picks, in order. */
        private fun runs(range: Span, isFree: (Int) -> Boolean): List<Span> {
            val runs = mutableListOf<Span>()
            var start: Int? = null
            for (block in range.lowerBound..range.upperBound) {
                if (block < range.upperBound && isFree(block)) {
                    if (start == null) start = block
                } else if (start != null) {
                    runs += Span(start, block)
                    start = null
                }
            }
            return runs
        }

        /** [logs] with [track]'s blocks in [range] taken out, and the logs in [track] that overlapped it. Only the logs
         *  [isCut] picks are taken out; the rest are kept whole. */
        private fun split(
            logs: List<BlockLog>, range: Span, track: Track, categories: List<BlockCategory>,
            isCut: (BlockLog) -> Boolean = { true },
        ): Pair<List<BlockLog>, List<BlockLog>> {
            val trackOf = categories.associateTracks()
            val kept = mutableListOf<BlockLog>()
            val cut = mutableListOf<BlockLog>()
            for (log in logs) {
                if (trackOf[log.categoryID] != track || !log.range.overlaps(range) || !isCut(log)) {
                    kept += log
                    continue
                }
                cut += log
                if (log.startIndex < range.lowerBound) kept += log.copy(length = range.lowerBound - log.startIndex)
                if (log.range.upperBound > range.upperBound) {
                    kept += BlockLog(
                        startIndex = range.upperBound, length = log.range.upperBound - range.upperBound,
                        categoryID = log.categoryID, note = log.note, source = log.source, templateID = log.templateID)
                }
            }
            return kept to cut
        }

        /**
         * Touching logs of the same category, source and note made one. Their order is kept, since logs that overlap
         * are layered in it when all else is even (see [DayGrid.cells]): two that join take the later one's place, as
         * the one logged last.
         */
        private fun joined(logs: List<BlockLog>): List<BlockLog> {
            val joined = mutableListOf<BlockLog>()
            for (next in logs) {
                var log = next
                while (true) {
                    val i = joined.indexOfFirst {
                        (it.range.upperBound == log.startIndex || log.range.upperBound == it.startIndex) &&
                            it.categoryID == log.categoryID && it.source == log.source && it.note == log.note &&
                            it.templateID == log.templateID
                    }
                    if (i < 0) break
                    val other = joined.removeAt(i)
                    log = log.copy(
                        id = if (other.startIndex < log.startIndex) other.id else log.id,
                        startIndex = minOf(other.startIndex, log.startIndex), length = other.length + log.length)
                }
                joined += log
            }
            return joined
        }

        private fun List<BlockCategory>.associateTracks(): Map<String, Track> {
            val tracks = HashMap<String, Track>()
            for (category in this) tracks.putIfAbsent(category.id, category.track)
            return tracks
        }
    }
}

/** Saves each day's logs as a JSON file in [directory], as the Swift app does. */
class LogStore(val directory: File) {
    /** The saved logs for [day], or an empty day. A file that can't be read is moved aside first, out of the days
     *  (which are ".json"), so saving the empty day doesn't write over it. */
    fun load(day: String, wakeMinute: Int): DayLog {
        val file = file(day)
        val text = try {
            file.readText()
        } catch (_: IOException) {
            return DayLog(day, wakeMinute)
        }
        return try {
            TimeBlockJson.decodeFromString(DayLog.serializer(), text)
        } catch (_: IllegalArgumentException) {
            file.renameTo(File(directory, "$day.${Instant.now().epochSecond}.unreadable"))
            DayLog(day, wakeMinute)
        }
    }

    /** The days with logs saved, oldest first. */
    fun savedDays(): List<String> =
        (directory.listFiles() ?: emptyArray()).filter { it.extension == "json" }.map { it.nameWithoutExtension }
            .filter { DayID.date(it) != null }.sorted()

    /** Writes [log] whole, so a file is never left half written. */
    fun save(log: DayLog) {
        directory.mkdirs()
        val temporary = File.createTempFile(log.day, ".saving", directory)
        temporary.writeText(TimeBlockJson.encodeToString(DayLog.serializer(), log))
        Files.move(
            temporary.toPath(), file(log.day).toPath(), StandardCopyOption.ATOMIC_MOVE,
            StandardCopyOption.REPLACE_EXISTING)
    }

    private fun file(day: String) = File(directory, "$day.json")
}
