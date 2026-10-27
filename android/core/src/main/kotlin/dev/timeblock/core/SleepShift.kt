package dev.timeblock.core

import kotlinx.serialization.Serializable
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sign

/**
 * Gets you to your schedule a step at a time instead of all at once: bedtime 01:00 to 23:00, 30 minutes a day, is
 * 00:30, 00:00, 23:30, then 23:00. The schedule in [AppSettings] is where you're heading; [from] is where you started,
 * and each day's schedule is a few steps along from it.
 *
 * Steps land on nights: the step on a day moves that day's bedtime, and wake time follows the next morning, so the
 * night between them is as long as before. A morning that's already gone never moves.
 */
@Serializable
data class SleepShift(
    /** The schedule you started from. */
    val from: Schedule,
    /** The day whose night takes the first step, as "2026-10-26" (see [Schedule.dayID]). */
    val startDay: String,
    /** How far wake time and bedtime move each step, in minutes: a multiple of a block. */
    val stepMinutes: Int = 30,
    /** Days between steps. */
    val everyDays: Int = 1,
    /** The end you set a time for; the other follows it or stays. Editing the shift starts from it again. */
    val leads: Schedule.End = Schedule.End.BED,
    /** Whether you set the day to be there by rather than the day to start. */
    val isByFinishDay: Boolean = false,
) {
    /** The schedule on [day]: wake time after the steps taken by the night before, bedtime after the steps taken by
     *  its own night. */
    fun schedule(day: String, target: Schedule): Schedule {
        val lastNight = DayID.adding(-1, day) ?: day
        return Schedule(
            wakeMinute = schedule(afterSteps = steps(lastNight), target = target).wakeMinute,
            bedMinute = schedule(afterSteps = steps(day), target = target).bedMinute)
    }

    /** Where the shift has got to by the morning of [day]: the steps taken by the night before. Tonight's step moves
     *  on from here. */
    fun position(day: String, target: Schedule): Schedule =
        schedule(afterSteps = steps(DayID.adding(-1, day) ?: day), target = target)

    /** Whether the night of [day] takes a step that moves its bedtime or the next morning's wake time. */
    fun movesOnNight(day: String, target: Schedule): Boolean =
        schedule(afterSteps = steps(day), target = target) != position(day, target)

    /** The first night from [day] on that takes a step, going by [everyDays]. */
    fun nextStepDay(from: String): String {
        val days = DayID.days(startDay, from)
        if (days == null || days <= 0) return startDay
        val every = max(1, everyDays)
        return DayID.adding((days + every - 1) / every * every, startDay) ?: from
    }

    /**
     * The shift carried on from where it's got to by the morning of [today], with its next step on the night of
     * [nextStepOn]: today's morning stays, and nothing before it changes that you'd still see. Later than tonight holds the
     * steps back a night or more, say after sleeping in.
     */
    fun resumed(today: String, nextStepOn: String, target: Schedule): SleepShift =
        copy(from = position(today, target), startDay = nextStepOn)

    /**
     * The shift carried on from [onto] as the times of [day], say after sleeping in or before it starts: it keeps
     * its target, step and pace, and takes its next step from the next night on, keeping its finish day when that's
     * what you set.
     */
    fun rebased(onto: Schedule, day: String, target: Schedule): SleepShift {
        val tomorrow = DayID.adding(1, day) ?: day
        var shift = copy(from = onto)
        shift = shift.copy(
            startDay = if (isByFinishDay) shift.restarted(finishDay(target), target) else nextStepDay(tomorrow))
        if ((DayID.days(tomorrow, shift.startDay) ?: 0) < 0) shift = shift.copy(startDay = tomorrow)
        return shift
    }

    /** The start day that gets this shift to [target] by [finishDay]. */
    private fun restarted(finishDay: String, target: Schedule): String =
        DayID.adding(-daysToFinish(target), finishDay) ?: finishDay

    /** Where [afterSteps] steps from [from] toward [target] get you. Wake time and bedtime each stop once they get
     *  there. */
    fun schedule(afterSteps: Int, target: Schedule): Schedule {
        val moved = afterSteps * stepMinutes
        val toward = { start: Int, end: Int ->
            val distance = distance(start, end)
            clock(start + distance.sign * min(abs(distance), moved))
        }
        return Schedule(toward(from.wakeMinute, target.wakeMinute), toward(from.bedMinute, target.bedMinute))
    }

    /** How many steps have been taken by the night of [day]: none before [startDay], then one more every
     *  [everyDays]. */
    fun steps(day: String): Int {
        val days = DayID.days(startDay, day)
        if (days == null || days < 0) return 0
        return days / max(1, everyDays) + 1
    }

    /** Steps it takes to get from [from] to [target]. */
    fun stepCount(target: Schedule): Int =
        max(steps(from.wakeMinute, target.wakeMinute), steps(from.bedMinute, target.bedMinute))

    /** The first day that's all on [target]: the day of the last bedtime step, or the morning after the last wake
     *  time step. */
    fun finishDay(target: Schedule): String = DayID.adding(daysToFinish(target), startDay) ?: startDay

    /** Whether [day] is on [target] already, so the shift is over. */
    fun isDone(day: String, target: Schedule): Boolean = (DayID.days(finishDay(target), day) ?: 0) >= 0

    /** Days from [startDay] to [finishDay]. */
    private fun daysToFinish(target: Schedule): Int {
        val nightOfStep = { step: Int -> (step - 1) * max(1, everyDays) }
        val bed = steps(from.bedMinute, target.bedMinute)
        val wake = steps(from.wakeMinute, target.wakeMinute)
        return max(if (bed > 0) nightOfStep(bed) else 0, if (wake > 0) nightOfStep(wake) + 1 else 0)
    }

    private fun steps(start: Int, end: Int): Int {
        val step = max(Schedule.BLOCK_MINUTES, stepMinutes)
        return (abs(distance(start, end)) + step - 1) / step
    }

    companion object {
        /** A shift that has you on [target] from [finishDay], starting as many steps before it as it takes. */
        fun finishingOn(
            from: Schedule, finishDay: String, target: Schedule, stepMinutes: Int = 30, everyDays: Int = 1,
            leads: Schedule.End = Schedule.End.BED,
        ): SleepShift {
            val shift = SleepShift(from, finishDay, stepMinutes, everyDays, leads)
            return shift.copy(startDay = shift.restarted(finishDay, target), isByFinishDay = true)
        }

        /** The shortest way round the clock from one time to another, in minutes: 01:00 to 23:00 is -120. */
        fun distance(from: Int, to: Int): Int {
            val day = Schedule.DAY_MINUTES
            return ((to - from) % day + day + day / 2) % day - day / 2
        }

        private fun clock(minute: Int): Int = (minute % Schedule.DAY_MINUTES + Schedule.DAY_MINUTES) % Schedule.DAY_MINUTES
    }
}
