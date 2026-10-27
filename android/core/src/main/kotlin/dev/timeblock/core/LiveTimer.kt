package dev.timeblock.core

import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/** A stretch a timer ran, to the second: from when it was started to when it was stopped, or up to now while it runs. */
@Serializable
data class TimerSession(
    val categoryID: String,
    @Serializable(with = AppleDateSerializer::class) val start: Instant,
    @Serializable(with = AppleDateSerializer::class) val end: Instant,
) {
    /** In seconds. */
    val duration: Double get() = end.secondsSince(start)

    /**
     * The blocks of [day] it ran during, any part of each, counted from [schedule]'s wake time; at least the block it
     * started in. Empty when it ran on other days, or only before wake time.
     */
    fun blocks(day: String, schedule: Schedule, zone: ZoneId = ZoneId.systemDefault()): Span {
        val wake = DayID.instant(schedule.wakeMinute, day, zone) ?: return Span.empty
        val dayEnd = DayID.instant(Schedule.DAY_MINUTES + schedule.rolloverMinute, day, zone) ?: return Span.empty
        val seconds = Schedule.BLOCK_MINUTES * 60.0
        val first = floor(start.secondsSince(wake) / seconds).toInt()
        val last = ceil(minOf(end, dayEnd).secondsSince(wake) / seconds).toInt()
        val lower = max(0, first)
        val upper = min(max(last, first + 1), floor(dayEnd.secondsSince(wake) / seconds).toInt())
        return if (lower < upper) Span(lower, upper) else Span(lower, lower)
    }

    companion object {
        /** A stretch shorter than this, in seconds, was a slip, such as a timer stopped as soon as it started, and logs
         *  nothing. */
        const val SHORTEST = 10.0
    }
}

/**
 * Logs an activity live: while it runs, every block it runs in holds its activity, alongside whatever else the block
 * holds. It counts up from zero, or down from a length and then on past zero, until it's stopped.
 */
@Serializable
data class LiveTimer(
    val id: String = UUID.randomUUID().toString().uppercase(),
    val categoryID: String,
    /** What it counts down from, in seconds, or null to count up. */
    val countdown: Double? = null,
    @Serializable(with = AppleDateSerializer::class) val startedAt: Instant,
) {
    /** How long it has run, in seconds. */
    fun elapsed(at: Instant): Double = max(0.0, at.secondsSince(startedAt))

    /** The time left on a countdown, below zero once it's over; null for a timer counting up. */
    fun remaining(at: Instant): Double? = countdown?.let { it - elapsed(at) }

    /** When a countdown gets to zero, which can have passed. */
    val zeroDate: Instant? get() = countdown?.let { startedAt.plusSeconds(it) }

    /** What it has run, up to [at]. */
    fun session(at: Instant): TimerSession = TimerSession(categoryID, startedAt, maxOf(startedAt, at))
}

/** A countdown's length, in minutes, as shown: "30 min", "1 h", "1 h 30 min". */
object CountdownLength {
    /** What countdowns start at until another default is set. */
    const val STANDARD = 30

    /** The lengths to pick in a click until others are starred. */
    val standardPresets = listOf(30, 60)

    /** The longest a countdown can be set to. */
    const val LONGEST = 24 * 60

    /** The blocks a countdown of [minutes] takes, any part of one counting, as a timer logs them: 21 minutes is 5. */
    fun blocks(minutes: Int): Int = (minutes + Schedule.BLOCK_MINUTES - 1) / Schedule.BLOCK_MINUTES

    fun text(minutes: Int): String {
        val hours = minutes / 60
        val rest = minutes % 60
        if (hours == 0) return "$rest min"
        return if (rest == 0) "$hours h" else "$hours h $rest min"
    }
}

object BlockClock {
    /** The start of the block containing [at], followed by the next [count] block starts. */
    fun boundaries(at: Instant, count: Int, zone: ZoneId = ZoneId.systemDefault()): List<Instant> {
        val time = at.atZone(zone).withSecond(0).withNano(0)
        val blockStart = time.minusMinutes((time.minute % Schedule.BLOCK_MINUTES).toLong()).toInstant()
        return (0..count).map { blockStart.plusSeconds(it * Schedule.BLOCK_MINUTES * 60L) }
    }
}
