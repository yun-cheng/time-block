package dev.timeblock.core

import kotlin.math.max

/** How the UI should feel, driven by how many blocks are left before bedtime. Later moods are worse. */
enum class Mood {
    CALM,

    /** The last stretch before bed, set aside to get ready for sleep (30 minutes to start). */
    WIND_DOWN,

    /** Up to 30 minutes past bedtime. */
    UNEASY,

    /** Up to 2 hours past bedtime. */
    DREAD,

    /** More than 2 hours past bedtime. */
    NIGHTMARE;

    companion object {
        /** [windDownBlocks] is how many blocks before bed winding down takes; with none, calm lasts until bedtime. */
        fun of(blocksLeft: Int, windDownBlocks: Int = DayStatus.STANDARD_WIND_DOWN_BLOCKS): Mood = when {
            blocksLeft >= max(1, windDownBlocks + 1) -> CALM
            blocksLeft >= 1 -> WIND_DOWN
            blocksLeft >= -6 -> UNEASY
            blocksLeft >= -24 -> DREAD
            else -> NIGHTMARE
        }
    }
}

/** Where "now" sits in a day's blocks. */
data class DayStatus(
    val schedule: Schedule,
    /** Minute on the day's timeline (see [Schedule.timelineMinute]). For a day that's over, where it ended. */
    val nowMinute: Int,
    /** The blocks just before bedtime set aside to get ready for sleep. */
    val windDownBlocks: Int = STANDARD_WIND_DOWN_BLOCKS,
    /** Whether the day is over, a past day: every block has passed, and none is in progress. */
    val isOver: Boolean = false,
    /** Whether the day is still to come: no block has started. */
    val isAhead: Boolean = false,
) {
    /** The block [nowMinute] falls in, counted from wake time; null before waking. */
    private val reachedIndex: Int?
        get() = if (nowMinute >= schedule.wakeMinute) (nowMinute - schedule.wakeMinute) / Schedule.BLOCK_MINUTES else null

    /** The block in progress, counted from wake time; null before waking and on a day that's over. */
    val currentIndex: Int? get() = if (isOver) null else reachedIndex

    /** Blocks that have fully passed since waking, including any past bedtime. */
    val blocksUsed: Int get() = reachedIndex ?: 0

    /** Blocks started after bedtime, including the one in progress. */
    val overtimeBlocks: Int get() = max(0, (reachedIndex ?: 0) - schedule.awakeBlocks + if (isOver) 0 else 1)

    /**
     * Blocks left before bedtime, counting the one in progress. Goes from 1 straight to -1 at bedtime, so a negative
     * number is always the count of blocks taken from sleep.
     */
    val blocksLeft: Int
        get() {
            val index = reachedIndex ?: return schedule.awakeBlocks
            return if (index < schedule.awakeBlocks) schedule.awakeBlocks - index else -overtimeBlocks
        }

    /** Calm on a day that's over or still to come: it's too late, or too soon, for it to matter. */
    val mood: Mood get() = if (isOver || isAhead) Mood.CALM else Mood.of(blocksLeft, windDownBlocks)

    /** The blocks set aside to wind down, ending at bedtime. A day shorter than that winds down all day. */
    val windDownRange: Span get() = Span(max(0, schedule.awakeBlocks - windDownBlocks), schedule.awakeBlocks)

    /** Blocks the grid shows: the waking day plus any overtime already started. */
    val visibleBlocks: Int get() = schedule.awakeBlocks + overtimeBlocks

    companion object {
        /** 30 minutes. */
        const val STANDARD_WIND_DOWN_BLOCKS = 6

        /** A day still to come. */
        fun ahead(schedule: Schedule, windDownBlocks: Int = STANDARD_WIND_DOWN_BLOCKS) = DayStatus(
            schedule, schedule.wakeMinute - Schedule.BLOCK_MINUTES, windDownBlocks, isAhead = true)

        /** A past day, which ran to bedtime or, when blocks after it are logged, to the end of the last of them. */
        fun ended(schedule: Schedule, afterBlocks: Int, windDownBlocks: Int = STANDARD_WIND_DOWN_BLOCKS) = DayStatus(
            schedule, schedule.wakeMinute + max(afterBlocks, schedule.awakeBlocks) * Schedule.BLOCK_MINUTES,
            windDownBlocks, isOver = true)
    }
}
