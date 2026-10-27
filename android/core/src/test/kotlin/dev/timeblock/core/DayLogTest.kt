package dev.timeblock.core

import java.io.File
import java.nio.file.Files
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DayLogTest {
    private val schedule = Schedule.standard

    private data class Paint(val range: Span, val category: String?, val track: Track)

    private fun painted(vararg steps: Paint): DayLog = steps.fold(DayLog("2026-10-24", schedule.wakeMinute)) { log, step ->
        log.set(step.range, step.category, step.track, schedule)
    }

    private fun activity(range: Span, category: String?) = Paint(range, category, Track.ACTIVITY)
    private fun body(range: Span, category: String?) = Paint(range, category, Track.BODY)

    /** The logs in time order (they're kept in the order they're layered in). */
    private fun summary(log: DayLog): List<String> = log.logs.sortedBy { it.startIndex }.map { log ->
        "${log.categoryID} ${log.range}" + (log.note?.let { " \"$it\"" } ?: "")
    }

    private fun temporaryDirectory(): File = Files.createTempDirectory("days").toFile()

    @Test fun paintingNextToARunJoinsIt() {
        val log = painted(activity(0 upTo 3, "work"), activity(3 upTo 4, "work"), activity(4 upTo 6, "meal"))
        assertEquals(listOf("work 0..<4", "meal 4..<6"), summary(log))
    }

    @Test fun paintingInsideARunSplitsIt() {
        val log = painted(activity(0 upTo 10, "work"), activity(4 upTo 6, "coffee"))
        assertEquals(listOf("work 0..<4", "coffee 4..<6", "work 6..<10"), summary(log))
    }

    @Test fun clearingRemovesOnlyThatTrack() {
        val log = painted(activity(0 upTo 10, "work"), body(0 upTo 10, "sitting"), activity(2 upTo 8, null))
        assertEquals(setOf("work 0..<2", "work 8..<10", "sitting 0..<10"), summary(log).toSet())
    }

    @Test fun blocksKeepTheirClockTimeWhenWakeTimeMoves() {
        val log = painted(activity(12 upTo 14, "meal")) // 08:00–08:10 with a 07:00 wake
        val later = Schedule(wakeMinute = 7 * 60 + 30, bedMinute = 23 * 60)
        assertEquals(listOf(6 upTo 8), log.logs(later).map { it.range })
        assertEquals(8 * 60, later.clockMinute(6))
    }

    @Test fun lateNightStillBelongsToTheDayBefore() {
        val utc = ZoneId.of("UTC")
        fun date(day: Int, hour: Int) = ZonedDateTime.of(2026, 10, day, hour, 30, 0, 0, utc).toInstant()
        assertEquals("2026-10-24", schedule.dayID(date(25, 1), utc)) // 01:30, before the 05:00 rollover
        assertEquals("2026-10-25", schedule.dayID(date(25, 6), utc))
    }

    @Test fun logsSurviveASaveAndLoad() {
        val directory = temporaryDirectory()
        try {
            val store = LogStore(directory)
            val log = painted(activity(0 upTo 6, "exercise"), body(0 upTo 6, "exercising"))
            store.save(log)
            assertEquals(log, store.load(log.day, 0))
            assertTrue(store.load("2026-10-25", 420).logs.isEmpty())
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test fun aDayThatCantBeReadIsKeptAside() {
        val directory = temporaryDirectory()
        try {
            val store = LogStore(directory)
            File(directory, "2026-10-24.json").writeText("not a day")
            assertTrue(store.load("2026-10-24", 420).logs.isEmpty())
            // Saving the empty day leaves what couldn't be read where it was moved, out of the days.
            store.save(DayLog("2026-10-24", 420))
            val files = directory.list()!!.toList()
            assertTrue(files.any { it.startsWith("2026-10-24.") && it.endsWith(".unreadable") })
            assertEquals(listOf("2026-10-24"), store.savedDays())
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test fun savedDaysAreListedOldestFirst() {
        val directory = temporaryDirectory()
        try {
            val store = LogStore(directory)
            for (day in listOf("2026-10-25", "2026-09-30", "2026-10-24")) store.save(DayLog(day, 420))
            File(directory, "notes.json").writeText("")
            assertEquals(listOf("2026-09-30", "2026-10-24", "2026-10-25"), store.savedDays())
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test fun aDayKeepsItsScheduleWithItsLogs() {
        assertEquals(schedule, painted(activity(0 upTo 3, "work")).schedule)
        // Days saved before schedules were kept with them have none.
        val old = """{"day":"2026-10-20","wakeMinute":420,"logs":[]}"""
        assertNull(TimeBlockJson.decodeFromString(DayLog.serializer(), old).schedule)
    }

    @Test fun aPastDayHasEveryBlockPastAndRunsToItsLastLog() {
        var log = painted(activity(0 upTo 3, "work"))
        val settings = AppSettings(schedule).copy(schedule = Schedule(wakeMinute = 8 * 60, bedMinute = 22 * 60))
        // The day keeps the schedule it had, 07:00–23:00, whatever the settings say now.
        var past = settings.snapshot(log, "2026-10-26")
        assertEquals(schedule, past.status.schedule)
        assertEquals(schedule.awakeBlocks, past.cells.size)
        assertTrue(past.cells.all { it.phase == BlockCell.Phase.PAST })
        assertTrue(past.status.currentIndex == null && past.status.mood == Mood.CALM && past.status.overtimeBlocks == 0)
        // Blocks logged past bedtime show as the day's overtime.
        log = log.set(schedule.awakeBlocks upTo schedule.awakeBlocks + 4, "work", Track.ACTIVITY, schedule)
        past = settings.snapshot(log, "2026-10-26")
        assertEquals(schedule.awakeBlocks + 4, past.cells.size)
        assertTrue(past.status.overtimeBlocks == 4 && past.pastOvertimeCount == 4)
        assertEquals(Mood.CALM, past.status.mood)
    }

    @Test fun aDayAheadHasNoBlockStartedAndFollowsTheSettings() {
        val log = painted(activity(24 upTo 27, "work")) // 2026-10-24 09:00–09:15, logged with a 07:00 wake
        val later = Schedule(wakeMinute = 8 * 60, bedMinute = 22 * 60)
        val ahead = AppSettings(later).snapshot(log, "2026-10-23")
        assertTrue(ahead.status.isAhead && ahead.status.currentIndex == null && ahead.status.mood == Mood.CALM)
        // Still to come, it takes the schedule the settings give it now, and its blocks keep their clock times.
        assertEquals(later, ahead.status.schedule)
        assertEquals(later.awakeBlocks, ahead.cells.size)
        assertTrue(ahead.cells.all { it.phase == BlockCell.Phase.FUTURE })
        assertEquals(listOf(12, 13, 14), ahead.cells.filter { it.categoryID == "work" }.map { it.index })
    }

    private fun snapshot(log: DayLog, nowMinute: Int = 9 * 60, favorites: List<String>? = null) =
        DaySnapshot(DayStatus(schedule, nowMinute), log.logs(schedule), BlockCategories.defaults, favorites)

    @Test fun unloggedRunReachesBackToTheLastLog() {
        val snapshot = snapshot(painted(activity(0 upTo 4, "work")), nowMinute = 7 * 60 + 50)
        assertEquals(4 upTo 10, snapshot.unloggedRun(10))
        assertEquals(4 upTo 4, snapshot.unloggedRun(4))
    }

    @Test fun runCoversTheWholeStretchOfOneCategory() {
        val snapshot = snapshot(painted(activity(0 upTo 4, "work"), activity(4 upTo 6, "coffee"), activity(6 upTo 9, "work")))
        assertEquals(0 upTo 4, snapshot.run(2))
        assertEquals(4 upTo 6, snapshot.run(5))
        // 09:00 is block 24: the gap so far (with the block in progress), the empty rest of the day and the time to wind
        // down before bed are apart.
        val windDown = snapshot.status.windDownRange
        assertEquals(9 upTo 25, snapshot.run(20))
        assertEquals(25 upTo windDown.lowerBound, snapshot.run(30))
        assertEquals(windDown, snapshot.run(windDown.lowerBound))
    }

    @Test fun resizingARunTakesInOrLetsGoOfBlocks() {
        var log = painted(activity(0 upTo 4, "work"), activity(6 upTo 8, "coffee"), body(0 upTo 10, "sit"))
        log = log.setNote("deep", 0 upTo 4, Track.ACTIVITY, schedule)
        // Longer, over what was there.
        log = log.resize(0 upTo 4, 0 upTo 7, Track.ACTIVITY, schedule)
        assertEquals(listOf("sit 0..<10", "work 0..<7 \"deep\"", "coffee 7..<8"), summary(log))
        // Shorter from the start, which clears what it lets go.
        log = log.resize(0 upTo 7, 3 upTo 7, Track.ACTIVITY, schedule)
        assertEquals(listOf("sit 0..<10", "work 3..<7 \"deep\"", "coffee 7..<8"), summary(log))
        // Not one category: nothing changes.
        log = log.resize(3 upTo 8, 3 upTo 9, Track.ACTIVITY, schedule)
        assertEquals(listOf("sit 0..<10", "work 3..<7 \"deep\"", "coffee 7..<8"), summary(log))
    }

    @Test fun movingBlocksTakesTheirGapsAndNotesAlong() {
        var log = painted(
            activity(0 upTo 3, "work"), activity(4 upTo 6, "coffee"), activity(6 upTo 12, "meal"), body(0 upTo 12, "sit"))
        log = log.setNote("deep", 0 upTo 3, Track.ACTIVITY, schedule)
        // Work, a gap and coffee, 6 blocks later: over the meal, leaving the first blocks empty.
        log = log.move(0 upTo 6, 6, Track.ACTIVITY, schedule)
        assertEquals(listOf("sit 0..<12", "work 6..<9 \"deep\"", "coffee 10..<12"), summary(log))
        // Back over part of itself.
        log = log.move(6 upTo 12, -2, Track.ACTIVITY, schedule)
        assertEquals(listOf("sit 0..<12", "work 4..<7 \"deep\"", "coffee 8..<10"), summary(log))
        // Nothing logged: nothing moves, and nothing is cleared where it would land.
        log = log.move(0 upTo 4, 4, Track.ACTIVITY, schedule)
        assertEquals(listOf("sit 0..<12", "work 4..<7 \"deep\"", "coffee 8..<10"), summary(log))
    }

    @Test fun clearingTakesTheRunOrTheSelectionItIsIn() {
        val snapshot = snapshot(painted(activity(0 upTo 4, "work"), activity(4 upTo 6, "coffee")))
        assertEquals(0 upTo 4, snapshot.clearable(2)?.range)
        assertEquals(0 upTo 4, snapshot.clearable(2, selection = 3 upTo 8)?.range)
        assertEquals(3 upTo 8, snapshot.clearable(5, selection = 3 upTo 8)?.range)
        // Nothing logged to clear.
        assertNull(snapshot.clearable(10))
        assertNull(snapshot.clearable(10, selection = 8 upTo 12))
        assertNull(snapshot.clearable(-1))
    }

    @Test fun aNoteCoversExactlyTheBlocksItIsWrittenOn() {
        var log = painted(activity(0 upTo 10, "work"), body(0 upTo 10, "sitting"))
        log = log.setNote("Wrote PLAN.md", 2 upTo 5, Track.ACTIVITY, schedule)
        assertEquals(
            setOf("work 0..<2", "work 2..<5 \"Wrote PLAN.md\"", "work 5..<10", "sitting 0..<10"), summary(log).toSet())
        log = log.setNote("  ", 0 upTo 10, Track.ACTIVITY, schedule)
        assertEquals(setOf("work 0..<10", "sitting 0..<10"), summary(log).toSet())
    }

    @Test fun aRunGivenAnotherCategoryKeepsItsNote() {
        var log = painted(activity(0 upTo 10, "work"))
        log = log.setNote("Standup", 2 upTo 4, Track.ACTIVITY, schedule)
        log = log.set(2 upTo 4, "meeting", Track.ACTIVITY, schedule)
        assertEquals(listOf("work 0..<2", "meeting 2..<4 \"Standup\"", "work 4..<10"), summary(log))
        // Painting over part of it doesn't take the note along.
        log = log.set(3 upTo 5, "coffee", Track.ACTIVITY, schedule)
        assertEquals(listOf("work 0..<2", "meeting 2..<3 \"Standup\"", "coffee 3..<5", "work 5..<10"), summary(log))
    }

    @Test fun aNoteMakesItsOwnRun() {
        val log = painted(activity(0 upTo 10, "work")).setNote("Review", 4 upTo 6, Track.ACTIVITY, schedule)
        val snapshot = snapshot(log)
        assertEquals(0 upTo 4, snapshot.run(1))
        assertEquals(4 upTo 6, snapshot.run(4))
        assertEquals("Review", snapshot.cells[5].note)
    }

    @Test fun onlyFavoritesOfTheTrackAreInThePalette() {
        val snapshot = snapshot(
            painted(activity(0 upTo 2, "snack"), activity(2 upTo 4, "lunch")), favorites = listOf("lunch", "sitting", "work"))
        // By group, whatever order they were starred in: Work comes before Life.
        assertEquals(listOf("work", "lunch"), snapshot.favorites.map { it.id })
        assertEquals("snack", snapshot.cells[0].categoryID)
        // Snack and Lunch are both Life, and are summed up together.
        assertEquals("Life" to 4, snapshot.legendTotals.first().let { it.name to it.blocks })
    }
}
