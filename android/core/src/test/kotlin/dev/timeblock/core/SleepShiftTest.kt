package dev.timeblock.core

import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class SleepShiftTest {
    /** 09:00–01:00, heading to 07:00–23:00. */
    private val late = Schedule(wakeMinute = 9 * 60, bedMinute = 60)
    private val target = Schedule.standard

    private fun bedtimes(shift: SleepShift, days: IntRange): List<String> = days.map {
        Schedule.clockText(schedule(shift, it).bedMinute)
    }

    private fun schedule(shift: SleepShift, offset: Int) = shift.schedule(DayID.adding(offset, "2026-10-26")!!, target)

    @Test fun bedtimeStepsOverMidnightToTheTarget() {
        val shift = SleepShift(late, "2026-10-26")
        assertEquals(listOf("01:00", "00:30", "00:00", "23:30", "23:00", "23:00"), bedtimes(shift, -1..4))
        assertEquals(4, shift.stepCount(target))
        // The last step is Thursday night; Friday morning is on 07:00 too.
        assertEquals("2026-10-30", shift.finishDay(target))
        assertFalse(shift.isDone("2026-10-29", target))
        assertTrue(shift.isDone("2026-10-30", target))
    }

    @Test fun wakeTimeFollowsTheNextMorningSoEveryNightIsAsLong() {
        val shift = SleepShift(late, "2026-10-26")
        // The first day keeps its morning and takes the first step at night.
        assertEquals(Schedule(wakeMinute = 9 * 60, bedMinute = 30), schedule(shift, 0))
        assertEquals(Schedule(wakeMinute = 8 * 60 + 30, bedMinute = 0), schedule(shift, 1))
        for (offset in 0..5) {
            val night = (schedule(shift, offset).wakeMinute - schedule(shift, offset - 1).bedMinute + 24 * 60) % (24 * 60)
            assertEquals(8 * 60, night)
        }
        // The rollover follows wake time, so 05:30 Tuesday is still Monday night.
        assertEquals(6 * 60 + 30, schedule(shift, 1).rolloverMinute)
    }

    @Test fun aFixedWakeTimeStaysPut() {
        val shift = SleepShift(Schedule(wakeMinute = 7 * 60, bedMinute = 60), "2026-10-26", stepMinutes = 60)
        val schedules = (0..2).map { schedule(shift, it) }
        assertEquals(listOf(420, 420, 420), schedules.map { it.wakeMinute })
        assertEquals(listOf(0, 23 * 60, 23 * 60), schedules.map { it.bedMinute })
        assertEquals("2026-10-27", shift.finishDay(target))
    }

    @Test fun aWakeTimeShiftMovesNoMorningOnItsFirstDay() {
        val shift = SleepShift(Schedule(wakeMinute = 9 * 60, bedMinute = 23 * 60), "2026-10-26", stepMinutes = 60)
        assertEquals(listOf(540, 480, 420, 420), (0..3).map { schedule(shift, it).wakeMinute })
        assertEquals("2026-10-28", shift.finishDay(target))
    }

    @Test fun stepsCanBeDaysApartAndLater() {
        val early = Schedule(wakeMinute = 6 * 60, bedMinute = 22 * 60)
        val shift = SleepShift(early, "2026-10-26", stepMinutes = 45, everyDays = 2)
        assertEquals(listOf("22:45", "22:45", "23:00", "23:00", "23:00"), bedtimes(shift, 0..4))
        assertEquals("2026-10-29", shift.finishDay(target))
    }

    @Test fun settingsUseEachDaysSchedule() {
        val settings = AppSettings(target, sleepShift = SleepShift(late, "2026-10-26"))
        assertEquals(late, settings.schedule("2026-10-25"))
        assertEquals(0, settings.schedule("2026-10-27").bedMinute)
        val decoded = TimeBlockJson.decodeFromString(
            AppSettings.serializer(), TimeBlockJson.encodeToString(AppSettings.serializer(), settings))
        assertEquals(settings, decoded)
        assertEquals(target, settings.copy(sleepShift = null).schedule("2026-10-27"))
    }

    @Test fun aMomentBelongsToTheDayItsDatesRolloverSays() {
        val settings = AppSettings(target, sleepShift = SleepShift(late, "2026-10-26"))
        val zone = ZoneId.systemDefault()
        fun at(day: Int, hour: Int, minute: Int) = ZonedDateTime.of(2026, 10, day, hour, minute, 0, 0, zone).toInstant()
        // Tuesday's rollover is 06:30 (wake 08:30), so 06:00 Tuesday is still Monday night.
        assertEquals("2026-10-26", settings.dayID(at(27, 6, 0)))
        assertEquals("2026-10-27", settings.dayID(at(27, 6, 30)))
        assertEquals(30, settings.schedule(at(26, 12, 0)).bedMinute)
    }

    @Test fun aShiftCanBeSetToFinishByADay() {
        val shift = SleepShift.finishingOn(late, "2026-10-31", target, everyDays = 2)
        assertEquals("2026-10-24", shift.startDay)
        assertEquals("2026-10-31", shift.finishDay(target))
        assertEquals("2026-10-30", SleepShift.finishingOn(late, "2026-10-31", target, stepMinutes = 120).startDay)
    }

    @Test fun holdingTonightPutsEachStepANightLater() {
        val shift = SleepShift(late, "2026-10-26")
        assertEquals(Schedule(wakeMinute = 510, bedMinute = 30), shift.position("2026-10-27", target))
        assertTrue(shift.movesOnNight("2026-10-27", target))
        val held = shift.resumed("2026-10-27", nextStepOn = "2026-10-28", target = target)
        // Tuesday keeps its morning, and its night stays at Monday's bedtime.
        assertEquals(Schedule(wakeMinute = 510, bedMinute = 30), schedule(held, 1))
        assertEquals(Schedule(wakeMinute = 510, bedMinute = 0), schedule(held, 2))
        assertFalse(held.movesOnNight("2026-10-27", target))
        assertEquals("2026-10-31", held.finishDay(target))
        for (offset in 2..6) {
            val night = (schedule(held, offset).wakeMinute - schedule(held, offset - 1).bedMinute + 24 * 60) % (24 * 60)
            assertEquals(8 * 60, night)
        }
    }

    @Test fun resumingOnTheNextStepKeepsTheShiftAsItWas() {
        val shift = SleepShift(late, "2026-10-26", everyDays = 2)
        assertEquals("2026-10-26", shift.nextStepDay("2026-10-20"))
        assertEquals("2026-10-28", shift.nextStepDay("2026-10-27"))
        assertEquals("2026-10-28", shift.nextStepDay("2026-10-28"))
        val today = "2026-10-27"
        val resumed = shift.resumed(today, nextStepOn = shift.nextStepDay(today), target = target)
        assertEquals((1..10).map { schedule(shift, it) }, (1..10).map { schedule(resumed, it) })
        assertEquals(shift.finishDay(target), resumed.finishDay(target))
    }

    @Test fun aShiftKeepsHowItWasSetThroughAHoldAndSaving() {
        val shift = SleepShift.finishingOn(late, "2026-10-31", target, everyDays = 2, leads = Schedule.End.WAKE)
        val held = shift.resumed("2026-10-27", nextStepOn = "2026-10-29", target = target)
        assertTrue(held.leads == Schedule.End.WAKE && held.isByFinishDay)
        val encoded = TimeBlockJson.encodeToString(SleepShift.serializer(), held)
        assertEquals(held, TimeBlockJson.decodeFromString(SleepShift.serializer(), encoded))
        // Shifts saved before these were kept.
        val old = """{"from":{"wakeMinute":540,"bedMinute":60,"rolloverMinute":420},"startDay":"2026-10-26",""" +
            """"stepMinutes":30,"everyDays":1}"""
        val decoded = TimeBlockJson.decodeFromString(SleepShift.serializer(), old)
        assertTrue(decoded.leads == Schedule.End.BED && !decoded.isByFinishDay)
    }

    @Test fun changingTodayBeforeAShiftStartsMovesWhereItStartsFrom() {
        val shift = SleepShift(late, "2026-11-26")
        val now = Schedule(wakeMinute = 10 * 60, bedMinute = 2 * 60)
        val rebased = shift.rebased(now, "2026-10-26", target)
        assertEquals("2026-11-26", rebased.startDay)
        assertEquals(now, schedule(rebased, 0))
        assertEquals(6, rebased.stepCount(target))
    }

    @Test fun changingTodayMidShiftCarriesOnFromTheNewTimesTomorrowNight() {
        val shift = SleepShift(late, "2026-10-26")
        // Tuesday was to be 08:30–00:00; you slept in to 09:30 and keep tonight at 00:30.
        val now = Schedule(wakeMinute = 9 * 60 + 30, bedMinute = 30)
        val rebased = shift.rebased(now, "2026-10-27", target)
        assertEquals(now, schedule(rebased, 1))
        assertEquals(Schedule(wakeMinute = 9 * 60 + 30, bedMinute = 0), schedule(rebased, 2))
        assertEquals(Schedule(wakeMinute = 9 * 60, bedMinute = 23 * 60 + 30), schedule(rebased, 3))
    }

    @Test fun changingTodayKeepsTheFinishDayYouSet() {
        val shift = SleepShift.finishingOn(late, "2026-11-30", target)
        val now = Schedule(wakeMinute = 10 * 60, bedMinute = 2 * 60)
        val rebased = shift.rebased(now, "2026-10-26", target)
        assertEquals("2026-11-30", rebased.finishDay(target))
        assertEquals(now, schedule(rebased, 0))
        // Too close to make it by then: it starts tomorrow night instead.
        val soon = SleepShift.finishingOn(late, "2026-10-28", target).rebased(now, "2026-10-26", target)
        assertEquals("2026-10-27", soon.startDay)
    }

    @Test fun eitherEndCanLeadAndTheOtherFollowOrStay() {
        assertEquals(target, late.moving(Schedule.End.BED, 23 * 60, keepsSleep = true))
        assertEquals(target, late.moving(Schedule.End.WAKE, 7 * 60, keepsSleep = true))
        assertEquals(Schedule(wakeMinute = 7 * 60, bedMinute = 60), late.moving(Schedule.End.WAKE, 7 * 60, keepsSleep = false))
        assertEquals(
            Schedule(wakeMinute = 9 * 60, bedMinute = 23 * 60), late.moving(Schedule.End.BED, 23 * 60, keepsSleep = false))
    }

    @Test fun distanceTakesTheShortWayRound() {
        assertEquals(-120, SleepShift.distance(60, 23 * 60))
        assertEquals(120, SleepShift.distance(23 * 60, 60))
        assertEquals(0, SleepShift.distance(7 * 60, 7 * 60))
    }
}
