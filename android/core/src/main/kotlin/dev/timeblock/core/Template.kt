package dev.timeblock.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.UUID
import kotlin.math.max

/**
 * Time that comes back on given days, such as Lunch at 12:30 on weekdays. Each of those days it's pre-logged in
 * whatever blocks are free then: hollow until the time comes, then logged, unless you paint over it.
 */
@Serializable
data class Template(
    val id: String = "template-${UUID.randomUUID().toString().uppercase()}",
    val categoryID: String,
    /** What its start is counted from: a clock time, the day's wake time or bedtime, or the end of an activity. */
    val anchor: Anchor = Anchor.CLOCK,
    /** The activity it starts after, when it's anchored to one. */
    val afterCategoryID: String? = null,
    /** Clock minute it starts at (0..<1440), on a block boundary, when it's anchored to the clock. Kept when it's
     *  anchored elsewhere, so going back to a clock time finds it again. */
    val startMinute: Int = 12 * 60,
    /** Minutes after waking, before bed, or after the activity it follows ends, that it starts at, on a block
     *  boundary. */
    val offset: Int = 0,
    /** In blocks. */
    val length: Int,
    /** The days it comes back on, as Swift `Calendar` weekdays: 1 is Sunday, 7 Saturday. */
    val weekdays: Set<Int> = everyDay,
    /** Paused templates stay listed but pre-log nothing. */
    val isEnabled: Boolean = true,
    /** Whether a notification says when it starts. */
    val notifies: Boolean = false,
) {
    @Serializable
    enum class Anchor {
        /** At a clock time, such as Lunch at 12:30. */
        @SerialName("clock") CLOCK,

        /** A while after waking, such as Breakfast 30 minutes after, whenever that is. */
        @SerialName("wake") WAKE,

        /** A while before bed, such as Reading 45 minutes before. */
        @SerialName("bed") BED,

        /** A while after an activity ends, such as a Shower 15 minutes after the Gym: each time that day it's logged or
         *  pre-logged, wherever that is. */
        @SerialName("after") AFTER,
    }

    /**
     * The blocks it covers on a day with [schedule], cut to the waking day. One that starts after an activity needs
     * [following], the block that activity ends at that day, and covers none without it.
     */
    fun range(schedule: Schedule, following: Int? = null): Span {
        val start = when (anchor) {
            Anchor.CLOCK -> schedule.blockIndex(startMinute)
            Anchor.WAKE -> offset / Schedule.BLOCK_MINUTES
            Anchor.BED -> schedule.awakeBlocks - offset / Schedule.BLOCK_MINUTES
            Anchor.AFTER -> following?.let { it + offset / Schedule.BLOCK_MINUTES }
        } ?: return Span.empty
        val range = Span(start, start + length)
        return range.clamped(Span(0, max(0, schedule.awakeBlocks)))
    }

    /** Clock minute it starts at on a day with [schedule]; after an activity that ends at block [following], or, with
     *  none, the one it was last at a clock time. */
    fun startMinute(schedule: Schedule, following: Int? = null): Int = when (anchor) {
        Anchor.CLOCK -> startMinute
        Anchor.WAKE -> (schedule.wakeMinute + offset) % Schedule.DAY_MINUTES
        Anchor.BED -> ((schedule.bedMinute - offset) % Schedule.DAY_MINUTES + Schedule.DAY_MINUTES) % Schedule.DAY_MINUTES
        Anchor.AFTER ->
            following?.let { (schedule.wakeMinute + it * Schedule.BLOCK_MINUTES + offset) % Schedule.DAY_MINUTES } ?: startMinute
    }

    /**
     * Counts its start from [anchor] instead, and after the activity [afterCategoryID] for [Anchor.AFTER]: a clock
     * time keeps where it starts on a day with [schedule] (where the activity it follows ends at block [following]), after
     * waking or before bed start at [DEFAULT_OFFSET], not however far the clock time is from them, and after an
     * activity starts as it ends.
     */
    fun anchored(anchor: Anchor, afterCategoryID: String? = null, schedule: Schedule, following: Int? = null): Template {
        if (anchor == this.anchor && !(anchor == Anchor.AFTER && afterCategoryID != this.afterCategoryID)) return this
        val moved = when (anchor) {
            Anchor.CLOCK -> copy(startMinute = startMinute(schedule, following))
            Anchor.WAKE, Anchor.BED -> copy(offset = DEFAULT_OFFSET)
            Anchor.AFTER -> if (this.anchor != Anchor.AFTER) copy(offset = 0) else this
        }
        return moved.copy(anchor = anchor, afterCategoryID = if (anchor == Anchor.AFTER) afterCategoryID else null)
    }

    companion object {
        val everyDay: Set<Int> = (1..7).toSet()
        val weekdaysOnly: Set<Int> = (2..6).toSet()
        val weekends: Set<Int> = setOf(1, 7)

        /** What after waking and before bed start at: half an hour. */
        const val DEFAULT_OFFSET = 30

        /** Those that start after an activity, each after any of them that pre-log the activity it follows, so that's
         *  laid out first. Ones that follow each other round in a circle go last, as they come. */
        internal fun inLayingOrder(templates: List<Template>): List<Template> {
            var waiting = templates.filter { it.anchor == Anchor.AFTER }
            val ordered = mutableListOf<Template>()
            while (waiting.isNotEmpty()) {
                val ready = waiting.filter { template ->
                    waiting.none { it.id != template.id && it.categoryID == template.afterCategoryID }
                }
                val next = ready.ifEmpty { waiting }
                ordered += next
                waiting = waiting.filter { template -> next.none { it.id == template.id } }
            }
            return ordered
        }
    }
}
