package dev.timeblock.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.ZoneId
import kotlin.math.floor
import kotlin.math.max

/** A day's waking window. Times are minutes after midnight. */
@Serializable
data class Schedule(
    val wakeMinute: Int,
    /** A bedtime at or before [wakeMinute] is read as after midnight (e.g. 01:00). */
    val bedMinute: Int,
    /** Clock times before this still belong to the previous day, so 01:30 counts as "tonight", not tomorrow. */
    val rolloverMinute: Int = max(0, wakeMinute - 120),
) {
    /** One end of the waking day. */
    @Serializable
    enum class End {
        @SerialName("wake") WAKE,
        @SerialName("bed") BED,
    }

    /** Bedtime on the day's timeline, which keeps counting past midnight (01:00 → 1500). */
    val bedTimelineMinute: Int get() = if (bedMinute > wakeMinute) bedMinute else bedMinute + DAY_MINUTES

    val awakeBlocks: Int get() = (bedTimelineMinute - wakeMinute) / BLOCK_MINUTES

    /** Empty slots before the first block, so grid rows line up with clock hours (08:30 wake → 6). */
    val gridOffset: Int get() = (wakeMinute % 60) / BLOCK_MINUTES

    /** Clock hour (0–23) of a grid row whose rows line up with clock hours. */
    fun hour(ofRow: Int): Int = (wakeMinute / 60 + ofRow) % 24

    fun timelineMinute(clockMinute: Int): Int =
        if (clockMinute < rolloverMinute) clockMinute + DAY_MINUTES else clockMinute

    fun timelineMinute(at: Instant, zone: ZoneId = ZoneId.systemDefault()): Int {
        val time = at.atZone(zone)
        return timelineMinute(time.hour * 60 + time.minute)
    }

    /** The day a moment belongs to, as "2026-10-24". Before the rollover it is still the previous day. */
    fun dayID(at: Instant, zone: ZoneId = ZoneId.systemDefault()): String {
        val time = at.atZone(zone)
        val date = time.toLocalDate()
        return (if (time.hour * 60 + time.minute < rolloverMinute) date.minusDays(1) else date).toString()
    }

    /** Index of the block containing a clock time, counted from wake time. */
    fun blockIndex(clockMinute: Int): Int =
        floor((timelineMinute(clockMinute) - wakeMinute).toDouble() / BLOCK_MINUTES).toInt()

    /** Clock minute (0..<1440) at which a block starts. */
    fun clockMinute(ofBlock: Int): Int = (wakeMinute + ofBlock * BLOCK_MINUTES) % DAY_MINUTES

    /** This schedule with one end moved to [minute], and the other moved as far when [keepsSleep], so you sleep
     *  as long as before. */
    fun moving(end: End, minute: Int, keepsSleep: Boolean): Schedule {
        val moved = SleepShift.distance(if (end == End.WAKE) wakeMinute else bedMinute, minute)
        val move = { time: Int -> ((time + moved) % DAY_MINUTES + DAY_MINUTES) % DAY_MINUTES }
        return when (end) {
            End.WAKE -> Schedule(minute, if (keepsSleep) move(bedMinute) else bedMinute)
            End.BED -> Schedule(if (keepsSleep) move(wakeMinute) else wakeMinute, minute)
        }
    }

    companion object {
        const val BLOCK_MINUTES = 5
        const val BLOCKS_PER_HOUR = 60 / BLOCK_MINUTES
        const val DAY_MINUTES = 24 * 60

        val standard = Schedule(wakeMinute = 7 * 60, bedMinute = 23 * 60)

        /**
         * Snaps a time picker edit to a block boundary. Time pickers step minutes by one, so a ±1 minute change from a
         * block boundary (including the picker wrapping :00 down to :59) is a step to the next block; anything else,
         * like a typed time, rounds to the nearest block.
         */
        fun snappedMinute(old: Int, new: Int): Int {
            val snapped = when (new - old) {
                1, -59 -> old + BLOCK_MINUTES
                -1, 59 -> old - BLOCK_MINUTES
                else -> (new + BLOCK_MINUTES / 2) / BLOCK_MINUTES * BLOCK_MINUTES
            }
            return (snapped % DAY_MINUTES + DAY_MINUTES) % DAY_MINUTES
        }

        /** A minute of the day, or of the day's timeline past midnight, as a clock time: "07:30", "01:00". */
        fun clockText(minute: Int): String = "%02d:%02d".format(minute / 60 % 24, minute % 60)
    }
}

/** "1h 25m" for 17 blocks. */
fun blocksDurationText(blocks: Int): String = durationText(blocks * Schedule.BLOCK_MINUTES)

/** "45m", "1h", "1h 30m". */
fun durationText(minutes: Int): String {
    val (h, m) = minutes / 60 to minutes % 60
    if (h == 0) return "${m}m"
    return if (m == 0) "${h}h" else "${h}h ${m}m"
}
