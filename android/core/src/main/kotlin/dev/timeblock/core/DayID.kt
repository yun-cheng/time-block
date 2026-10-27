package dev.timeblock.core

import java.time.DateTimeException
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.temporal.ChronoUnit

/** Days as "2026-10-26", the way [Schedule.dayID] writes them. */
object DayID {
    fun date(day: String): LocalDate? {
        val parts = day.split("-").mapNotNull { it.toIntOrNull() }
        if (parts.size != 3) return null
        return try {
            LocalDate.of(parts[0], parts[1], parts[2])
        } catch (_: DateTimeException) {
            null
        }
    }

    fun string(date: LocalDate): String = date.toString()

    fun string(instant: Instant, zone: ZoneId = ZoneId.systemDefault()): String =
        LocalDate.ofInstant(instant, zone).toString()

    fun adding(days: Int, day: String): String? = date(day)?.plusDays(days.toLong())?.toString()

    fun days(from: String, to: String): Int? {
        val start = date(from) ?: return null
        val end = date(to) ?: return null
        return ChronoUnit.DAYS.between(start, end).toInt()
    }

    /**
     * The moment a minute of [day]'s timeline comes (see [Schedule.timelineMinute]), which counts on past midnight.
     * Read off the clock, so it's right on days the clocks change.
     */
    fun instant(timelineMinute: Int, day: String, zone: ZoneId = ZoneId.systemDefault()): Instant? {
        val date = date(day)?.plusDays((timelineMinute / Schedule.DAY_MINUTES).toLong()) ?: return null
        val minute = timelineMinute % Schedule.DAY_MINUTES
        return ZonedDateTime.of(date, LocalTime.of(minute / 60, minute % 60), zone).toInstant()
    }

    /** The day of the week, as a Swift `Calendar` weekday: 1 is Sunday, 7 Saturday. */
    fun weekday(day: String): Int? = date(day)?.let { it.dayOfWeek.value % 7 + 1 }
}
