package dev.timeblock.core

import dev.timeblock.core.BlockLog.Source.CALENDAR
import dev.timeblock.core.BlockLog.Source.MANUAL
import dev.timeblock.core.BlockLog.Source.TEMPLATE

/** A realistic day of logs for previews. */
object SampleDay {
    val categories: List<BlockCategory> get() = BlockCategories.defaults

    private class Entry(
        val from: String, val to: String, val category: String, val source: BlockLog.Source, val note: String? = null,
    )

    // Gaps (07:50–08:00, 12:45–13:00, 15:15–15:30) are left unlogged on purpose.
    private val entries = listOf(
        Entry("07:00", "07:30", "exercise", MANUAL),
        Entry("07:30", "07:50", "breakfast", TEMPLATE),
        Entry("08:00", "08:30", "commute", MANUAL),
        Entry("08:30", "10:00", "work", MANUAL),
        Entry("10:00", "10:10", "coffee", TEMPLATE),
        Entry("10:10", "10:30", "work", MANUAL),
        Entry("10:30", "11:00", "meeting", CALENDAR, "Standup"),
        Entry("11:00", "12:00", "work", MANUAL),
        Entry("12:00", "12:45", "lunch", TEMPLATE),
        Entry("13:00", "15:00", "work", MANUAL),
        Entry("15:00", "15:15", "coffee", TEMPLATE),
        Entry("15:30", "16:30", "meeting", CALENDAR, "Design review"),
        Entry("16:30", "18:00", "work", MANUAL),
        Entry("18:00", "18:30", "commute", MANUAL),
        Entry("18:30", "19:00", "rest", MANUAL),
        Entry("19:00", "19:45", "dinner", TEMPLATE),
        Entry("19:45", "21:30", "social", MANUAL),
        Entry("21:30", "02:59", "doomscroll", MANUAL),
        // Done at the same time as the above, so layered with it.
        Entry("08:00", "08:30", "podcast", MANUAL),
        Entry("12:15", "12:45", "social", TEMPLATE, "Lunch with Ana"),

        // Body track. 15:15–15:30 is left unlogged.
        Entry("07:00", "07:30", "exercising", MANUAL),
        Entry("07:30", "07:50", "sitting", MANUAL),
        Entry("07:50", "08:00", "standing", MANUAL),
        Entry("08:00", "08:10", "walking", MANUAL),
        Entry("08:10", "08:25", "sitting", MANUAL),
        Entry("08:25", "08:30", "walking", MANUAL),
        Entry("08:30", "10:30", "sitting", MANUAL),
        Entry("10:30", "11:00", "standing", MANUAL),
        Entry("11:00", "12:45", "sitting", MANUAL),
        Entry("12:45", "13:00", "walking", MANUAL, "Lunch walk"),
        Entry("13:00", "15:00", "sitting", MANUAL),
        Entry("15:00", "15:15", "standing", MANUAL),
        Entry("15:30", "18:00", "sitting", MANUAL),
        Entry("18:00", "18:10", "walking", MANUAL),
        Entry("18:10", "18:30", "sitting", MANUAL),
        Entry("18:30", "19:00", "lying", MANUAL),
        Entry("19:00", "19:45", "sitting", MANUAL),
        Entry("19:45", "20:30", "standing", MANUAL),
        Entry("20:30", "21:30", "sitting", MANUAL),
        Entry("21:30", "02:59", "lying", MANUAL, "Phone in bed"),
    )

    fun logs(schedule: Schedule, status: DayStatus): List<BlockLog> = entries.mapNotNull { entry ->
        val start = schedule.blockIndex(minute(entry.from))
        var end = schedule.blockIndex(minute(entry.to))
        if (entry.source == MANUAL) {
            // Manual logs only exist for time that has already happened.
            val current = status.currentIndex
            if (current == null || start > current) return@mapNotNull null
            end = minOf(end, current + 1)
        }
        if (end <= start) return@mapNotNull null
        BlockLog(startIndex = start, length = end - start, categoryID = entry.category, note = entry.note, source = entry.source)
    }

    fun snapshot(schedule: Schedule, nowMinute: Int, track: Track = Track.ACTIVITY): DaySnapshot {
        val status = DayStatus(schedule, nowMinute)
        return DaySnapshot(status, logs(schedule, status), categories, track = track)
    }

    private fun minute(hhmm: String): Int {
        val (hours, minutes) = hhmm.split(":").map(String::toInt)
        return hours * 60 + minutes
    }
}
