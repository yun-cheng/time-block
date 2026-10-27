package dev.timeblock.core

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DayStatusTest {
    private val schedule = Schedule.standard // 07:00–23:00

    private fun status(clockMinute: Int) = DayStatus(schedule, schedule.timelineMinute(clockMinute))

    @Test fun sixteenHourDayIs192Blocks() {
        assertEquals(192, schedule.awakeBlocks)
    }

    @Test fun beforeWakeTheWholeDayIsLeft() {
        val s = status(6 * 60)
        assertNull(s.currentIndex)
        assertEquals(192, s.blocksLeft)
        assertEquals(0, s.blocksUsed)
    }

    @Test fun blockInProgressCountsAsLeft() {
        assertEquals(192, status(7 * 60).blocksLeft)
        assertEquals(192, status(7 * 60 + 4).blocksLeft)
        assertEquals(191, status(7 * 60 + 5).blocksLeft)
    }

    @Test fun middleOfTheDay() {
        val s = status(15 * 60 + 20)
        assertEquals(100, s.currentIndex)
        assertEquals(100, s.blocksUsed)
        assertEquals(92, s.blocksLeft)
        assertEquals(Mood.CALM, s.mood)
    }

    @Test fun lastBlockBeforeBedIsWindDown() {
        val s = status(22 * 60 + 59)
        assertEquals(1, s.blocksLeft)
        assertEquals(Mood.WIND_DOWN, s.mood)
    }

    @Test fun goesNegativeAtBedtime() {
        val s = status(23 * 60)
        assertEquals(-1, s.blocksLeft)
        assertEquals(1, s.overtimeBlocks)
        assertEquals(193, s.visibleBlocks)
        assertEquals(Mood.UNEASY, s.mood)
    }

    @Test fun pastMidnightStillCountsAsToday() {
        assertEquals(24 * 60 + 40, schedule.timelineMinute(40))
        val s = status(40) // 00:40
        assertEquals(-21, s.blocksLeft)
        assertEquals(Mood.DREAD, s.mood)
    }

    @Test fun moodThresholds() {
        assertEquals(Mood.CALM, Mood.of(7))
        assertEquals(Mood.WIND_DOWN, Mood.of(6))
        assertEquals(Mood.WIND_DOWN, Mood.of(1))
        assertEquals(Mood.UNEASY, Mood.of(-6))
        assertEquals(Mood.DREAD, Mood.of(-7))
        assertEquals(Mood.DREAD, Mood.of(-24))
        assertEquals(Mood.NIGHTMARE, Mood.of(-25))
    }

    @Test fun windDownLastsAsLongAsSet() {
        assertEquals(Mood.CALM, Mood.of(13, windDownBlocks = 12))
        assertEquals(Mood.WIND_DOWN, Mood.of(12, windDownBlocks = 12))
        assertEquals(Mood.CALM, Mood.of(1, windDownBlocks = 0))
        assertEquals(Mood.UNEASY, Mood.of(0, windDownBlocks = 0))
        val hour = DayStatus(schedule, 22 * 60, windDownBlocks = 12)
        assertEquals(Mood.WIND_DOWN, hour.mood)
        assertEquals(180 upTo 192, hour.windDownRange)
    }

    @Test fun windDownBlocksAreMarkedBeforeBedtime() {
        val status = DayStatus(schedule, 23 * 60 + 10, windDownBlocks = 3)
        val cells = DayGrid.cells(status, emptyList())
        assertEquals(listOf(189, 190, 191), cells.filter { it.isWindDown }.map { it.index })
        assertTrue(DayStatus(schedule, 12 * 60, windDownBlocks = 0).windDownRange.isEmpty)
    }

    @Test fun windDownIsKeptInSettings() {
        val settings = AppSettings(schedule).copy(windDownMinutes = 45)
        assertEquals(30, AppSettings(schedule).windDownMinutes)
        val decoded = TimeBlockJson.decodeFromString(
            AppSettings.serializer(), TimeBlockJson.encodeToString(AppSettings.serializer(), settings))
        assertEquals(9, decoded.windDownBlocks)
        val log = DayLog("2026-10-26", schedule.wakeMinute).rebased(schedule)
        assertEquals(9, decoded.snapshot(Instant.now(), log).status.windDownBlocks)
    }

    @Test fun bedtimeAfterMidnight() {
        val late = Schedule(wakeMinute = 9 * 60, bedMinute = 60)
        assertEquals(25 * 60, late.bedTimelineMinute)
        assertEquals(192, late.awakeBlocks)
    }

    @Test fun rowsLineUpWithClockHours() {
        val halfPast = Schedule(wakeMinute = 8 * 60 + 30, bedMinute = 23 * 60)
        assertEquals(6, halfPast.gridOffset)
        assertEquals(8, halfPast.hour(0))
        assertEquals(0, halfPast.hour(16))
        assertEquals(0, schedule.gridOffset)
    }

    @Test fun eachTrackShowsOnlyItsOwnLogs() {
        val now = schedule.timelineMinute(15 * 60 + 20)
        val activity = SampleDay.snapshot(schedule, now, Track.ACTIVITY)
        val body = SampleDay.snapshot(schedule, now, Track.BODY)
        // 10:30 is a standup meeting in Activity and standing in Body.
        val standup = schedule.blockIndex(10 * 60 + 30)
        assertEquals("meeting", activity.cells[standup].categoryID)
        assertEquals("standing", body.cells[standup].categoryID)
        assertEquals("Sitting", body.legendTotals.first().name)
        assertEquals("Work", activity.legendTotals.first().name)
        // Two unbroken hours of sitting (08:30–10:30 and 13:00–15:00) is the longest so far.
        assertEquals(24, body.longestRun("sitting"))
    }

    @Test fun gridMarksPhasesAndLogs() {
        val s = status(15 * 60 + 20) // block 100
        val cells = DayGrid.cells(s, listOf(BlockLog(startIndex = 98, length = 4, categoryID = "work")))
        assertEquals(192, cells.size)
        assertTrue(cells[97].phase == BlockCell.Phase.PAST && cells[97].categoryID == null)
        assertTrue(cells[98].phase == BlockCell.Phase.PAST && cells[98].categoryID == "work")
        assertEquals(BlockCell.Phase.CURRENT, cells[100].phase)
        assertTrue(cells[101].phase == BlockCell.Phase.FUTURE && cells[101].categoryID == "work")
        assertNull(cells[102].categoryID)
    }

    @Test fun timePickerStepsMoveWholeBlocks() {
        val seven = 7 * 60
        assertEquals(seven + 5, Schedule.snappedMinute(seven, seven + 1)) // ▲ on minutes
        assertEquals(seven - 5, Schedule.snappedMinute(seven, seven + 59)) // ▼ wraps :00 to :59
        assertEquals(seven, Schedule.snappedMinute(seven + 5, seven + 4)) // ▼
        assertEquals(8 * 60, Schedule.snappedMinute(seven + 55, seven + 56)) // ▲ past :55
        assertEquals(8 * 60, Schedule.snappedMinute(seven, seven + 60)) // hour field
        assertEquals(seven + 30, Schedule.snappedMinute(seven, seven + 32)) // typed
        assertEquals(0, Schedule.snappedMinute(23 * 60 + 55, 23 * 60 + 56)) // wraps past midnight
        assertEquals(23 * 60 + 55, Schedule.snappedMinute(0, 59))
    }
}
