package dev.timeblock.core

import java.time.Instant
import java.time.ZoneId
import kotlin.math.max

/** A notification the day has coming: a routine starting, winding down, bedtime, or getting later past it. */
data class Reminder(
    /** Stays the same while what it says about stays put, so planning again replaces it rather than adding another. */
    val id: String,
    val date: Instant,
    val title: String,
    val body: String,
) {
    companion object {
        /** What every reminder's id starts with, telling them apart from timers' alarms. */
        const val ID_PREFIX = "reminder-"

        /** Minutes past bedtime to say so again, as the day turns to dread and then to nightmare. */
        val pastBedtimeMinutes = listOf(30, 120)
    }
}

/**
 * What [log]'s day has to notify you of after [after], in order: the routines that notify, where they're still
 * pre-logged, winding down and bedtime, and how far past bedtime it's got.
 */
fun AppSettings.reminders(log: DayLog, after: Instant, zone: ZoneId = ZoneId.systemDefault()): List<Reminder> {
    class Coming(val block: Int, val id: String, val title: String, val body: String)

    val schedule = schedule(log.day)
    val day = log.rebased(schedule)
    val names = buildMap { for (c in categories) putIfAbsent(c.id, c.name) }
    val clock = { block: Int -> Schedule.clockText(schedule.clockMinute(block)) }
    val coming = mutableListOf<Coming>()

    for (template in templates.filter { it.notifies }) {
        val ranges = if (template.anchor == Template.Anchor.AFTER) {
            day.ends(template).map { template.range(schedule, it) }
        } else {
            listOf(template.range(schedule))
        }
        val held = day.logs.filter { it.templateID == template.id }.flatMap { it.range }.toSet()
        for (range in ranges) {
            // Where it's still pre-logged: after anything that took its first blocks, and not at all when you logged
            // over the whole of it.
            val start = range.firstOrNull { it in held } ?: continue
            val end = range.lastOrNull { it in held }?.let { it + 1 } ?: range.upperBound
            coming += Coming(
                start, "${template.id}-$start", names[template.categoryID] ?: "Routine",
                "${clock(start)}–${clock(end)}, from your routine.")
        }
    }

    val bed = schedule.awakeBlocks
    if (notifiesWindDown && windDownBlocks > 0) {
        coming += Coming(
            max(0, bed - windDownBlocks), "wind-down", "Time to wind down",
            "Bedtime is at ${clock(bed)}. Get ready for sleep.")
    }
    if (notifiesBedtime) {
        val ahead = bedtimeNoticeMinutes / Schedule.BLOCK_MINUTES
        val notice = max(0, bed - ahead)
        if (ahead == 0) {
            coming += Coming(bed, "bedtime", "It's bedtime", "${clock(bed)}. Every block from now on is taken from sleep.")
        } else if (!(notifiesWindDown && windDownBlocks > 0 && notice == max(0, bed - windDownBlocks))) {
            // Coming as winding down starts, that says it already.
            coming += Coming(
                notice, "bedtime", "Bedtime in ${duration((bed - notice) * Schedule.BLOCK_MINUTES)}",
                "At ${clock(bed)}. Time to finish up and get ready for sleep.")
        }
        for (minutes in Reminder.pastBedtimeMinutes) {
            val past = if (minutes < 60) "$minutes minutes" else "${minutes / 60} hours"
            coming += Coming(
                bed + minutes / Schedule.BLOCK_MINUTES, "past-bedtime-$minutes", "$past past bedtime",
                if (minutes < 60) "$past taken from sleep so far. Stop now." else "You are borrowing from tomorrow.")
        }
    }

    return coming.mapNotNull { reminder ->
        val at = DayID.instant(schedule.wakeMinute + reminder.block * Schedule.BLOCK_MINUTES, log.day, zone)
            ?.takeIf { it.isAfter(after) } ?: return@mapNotNull null
        Reminder("${Reminder.ID_PREFIX}${log.day}-${reminder.id}", at, reminder.title, reminder.body)
    }.sortedBy { it.date }
}

/** "45 minutes", "1 hour", "1h 30m". */
private fun duration(minutes: Int): String {
    val (h, m) = minutes / 60 to minutes % 60
    return when {
        h == 0 -> "$m minutes"
        h == 1 && m == 0 -> "1 hour"
        m == 0 -> "$h hours"
        else -> "${h}h ${m}m"
    }
}
