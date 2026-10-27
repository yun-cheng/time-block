package dev.timeblock.core

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Timers logging activities live. */
class TimerTest {
    private val schedule = Schedule.standard
    private val day = "2026-10-24"
    private val zone: ZoneId = ZoneId.of("Europe/London")

    /** [clock] ("10:03:30") on the day. */
    private fun at(clock: String, dayOffset: Long = 0): Instant {
        val parts = clock.split(":").map(String::toInt)
        val date = LocalDate.parse(day).plusDays(dayOffset)
        return ZonedDateTime.of(date.year, date.monthValue, date.dayOfMonth, parts[0], parts[1], parts.getOrElse(2) { 0 }, 0, zone)
            .toInstant()
    }

    /** The block of the day starting at [clock] ("10:05"). */
    private fun block(clock: String): Int {
        val (hour, minute) = clock.split(":").map(String::toInt)
        return schedule.blockIndex(hour * 60 + minute)
    }

    private fun session(from: String, to: String, categoryID: String = "coding") = TimerSession(categoryID, at(from), at(to))

    private fun blocks(session: TimerSession, day: String = this.day) = session.blocks(day, schedule, zone)

    @Test fun aStretchTakesEveryBlockItTouches() {
        assertEquals(block("10:00") upTo block("10:35"), blocks(session("10:03", "10:31")))
    }

    @Test fun aStretchKeepsItsClockTimesOnDaysTheClocksChange() {
        // The clocks went forward an hour at 01:00 on 2026-03-29.
        fun clock(hour: Int, minute: Int) = ZonedDateTime.of(2026, 3, 29, hour, minute, 0, 0, zone).toInstant()
        val session = TimerSession("coding", clock(10, 0), clock(10, 30))
        assertEquals(block("10:00") upTo block("10:30"), blocks(session, "2026-03-29"))
    }

    @Test fun aStretchEndingOnABoundaryStopsThere() {
        assertEquals(block("10:00") upTo block("10:30"), blocks(session("10:00", "10:30")))
    }

    @Test fun aMomentTakesItsBlock() {
        assertEquals(block("10:00") upTo block("10:05"), blocks(session("10:03:10", "10:03:40")))
    }

    @Test fun timeBeforeWakeAndOnOtherDaysIsLeftOut() {
        assertEquals(0 upTo block("07:15"), blocks(session("06:40", "07:12")))
        assertTrue(blocks(session("10:00", "11:00"), "2026-10-25").isEmpty)
    }

    @Test fun aStretchPastMidnightStaysWithTheNightBefore() {
        val late = TimerSession("shows", at("23:50"), at("00:20", dayOffset = 1))
        assertEquals(block("23:50") upTo block("00:20"), blocks(late))
    }

    @Test fun aCountdownGoesOnPastZero() {
        val timer = LiveTimer(categoryID = "writing", countdown = 25 * 60.0, startedAt = at("09:00"))
        assertEquals(900.0, timer.remaining(at("09:10")))
        assertEquals(at("09:25"), timer.zeroDate)
        assertEquals(-120.0, timer.remaining(at("09:27")))
        assertNull(LiveTimer(categoryID = "coding", startedAt = at("09:00")).remaining(at("09:10")))
    }

    @Test fun aRecordedStretchStacksOnWhatTheBlocksHold() {
        val log = DayLog(day, schedule.wakeMinute)
            .set(block("10:00") upTo block("11:00"), "meeting", Track.ACTIVITY, schedule)
            .record(session("10:20", "10:31", "bathroom"), schedule, zone)
        val cells = DayGrid.cells(DayStatus(schedule, 12 * 60), log.logs)
        assertEquals(listOf("meeting"), cells[block("10:15")].categoryIDs)
        assertEquals(listOf("meeting", "bathroom"), cells[block("10:20")].categoryIDs)
        assertEquals(listOf("meeting", "bathroom"), cells[block("10:30")].categoryIDs)
        assertEquals(listOf("meeting"), cells[block("10:35")].categoryIDs)
        assertEquals(listOf(session("10:20", "10:31", "bathroom")), log.sessions)
    }

    @Test fun blocksHoldingTheActivityAlreadyKeepIt() {
        val log = DayLog(day, schedule.wakeMinute)
            .set(block("10:00") upTo block("10:10"), "coding", Track.ACTIVITY, schedule)
            .setNote("Parser", block("10:00") upTo block("10:10"), Track.ACTIVITY, schedule)
            .record(session("10:05", "10:22"), schedule, zone)
        assertEquals(listOf(block("10:00") upTo block("10:10"), block("10:10") upTo block("10:25")), log.logs.map { it.range })
        assertEquals("Parser", log.logs.first().note)
    }

    @Test fun aRunningTimerShowsUpToTheBlockInProgress() {
        val log = DayLog(day, schedule.wakeMinute)
        val timer = LiveTimer(categoryID = "coding", startedAt = at("10:03"))
        val snapshot = AppSettings.standard.snapshot(at("10:16"), log, timers = listOf(timer), zone = zone)
        assertTrue((block("10:00") upTo block("10:20")).all { snapshot.cells[it].categoryID == "coding" })
        assertNull(snapshot.cells[block("10:20")].categoryID)
        assertEquals(
            listOf(TimerSession("coding", at("10:03"), at("10:16"))),
            snapshot.sessions(listOf("coding"), block("10:10") upTo block("10:15"), zone))
    }

    @Test fun aCountdownTakesEveryBlockItTouches() {
        assertEquals(4, CountdownLength.blocks(20))
        assertEquals(5, CountdownLength.blocks(21))
        assertEquals(1, CountdownLength.blocks(1))
    }

    @Test fun countdownLengthsShowInHoursAndMinutes() {
        assertEquals("30 min", CountdownLength.text(30))
        assertEquals("1 h", CountdownLength.text(60))
        assertEquals("1 h 30 min", CountdownLength.text(90))
    }

    @Test fun daysSavedBeforeTimersStillLoad() {
        val json = """{"day":"2026-10-24","wakeMinute":420,"logs":[]}"""
        assertTrue(TimeBlockJson.decodeFromString(DayLog.serializer(), json).sessions.isEmpty())
    }

    @Test fun timesAreSavedAsSwiftSavesThem() {
        // Swift writes a Date as seconds since the start of 2001.
        val session = TimerSession("coding", Instant.parse("2001-01-01T00:01:00Z"), Instant.parse("2001-01-01T00:01:30.5Z"))
        val json = TimeBlockJson.encodeToString(TimerSession.serializer(), session)
        assertEquals("""{"categoryID":"coding","start":60.0,"end":90.5}""", json)
        assertEquals(session, TimeBlockJson.decodeFromString(TimerSession.serializer(), json))
    }
}
