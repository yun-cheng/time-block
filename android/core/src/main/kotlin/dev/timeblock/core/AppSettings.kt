package dev.timeblock.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import java.time.Instant
import java.time.ZoneId
import kotlin.math.max
import kotlin.math.roundToInt

/** User settings, shared by the app and its widget. */
@Serializable(with = AppSettingsSerializer::class)
data class AppSettings(
    /** The schedule you keep, or are heading to while [sleepShift] gets you there. A day's own is [schedule]. */
    val schedule: Schedule,
    /** The view shown in the app. Each widget picks its own. */
    val track: Track = Track.ACTIVITY,
    /** Starred activities (and postures). The palette shows these, by group; search finds the rest. */
    val favorites: List<String> = BlockCategories.defaultFavorites,
    /** Activities the user added to the built-in ones. */
    val customCategories: List<BlockCategory> = emptyList(),
    /** Groups the user added after the built-in ones. */
    val customGroups: List<CategoryGroup> = emptyList(),
    /** Built-in activities and postures as the user edited them, replacing the originals. */
    val editedCategories: List<BlockCategory> = emptyList(),
    /** Built-in groups as the user renamed or recolored them, replacing the originals. */
    val editedGroups: List<CategoryGroup> = emptyList(),
    /** Ids of activities (and postures) the user removed. They're kept, retired, so blocks logged with them keep their
     *  name and color, and can be put back. */
    val removedCategories: List<String> = emptyList(),
    /** Time pre-logged on the days it comes back on, such as meals and coffee. */
    val templates: List<Template> = emptyList(),
    /** Moves you to [schedule] a step at a time. */
    val sleepShift: SleepShift? = null,
    /** How the grid marks the time. */
    val grid: GridMarks = GridMarks.standard,
    /** Minutes before bedtime set aside to get ready for sleep, in steps of 5, or 0 for none. The grid tints them, and
     *  the day turns warm as they start. */
    val windDownMinutes: Int = DayStatus.STANDARD_WIND_DOWN_BLOCKS * Schedule.BLOCK_MINUTES,
    /** Whether a notification says when winding down starts. */
    val notifiesWindDown: Boolean = true,
    /** Whether notifications say when it's bedtime, and as it gets later past it. */
    val notifiesBedtime: Boolean = true,
    /** Minutes before bedtime that the bedtime notification comes, in steps of 5, or 0 for at bedtime. */
    val bedtimeNoticeMinutes: Int = 0,
) {
    /** See [windDownMinutes]. */
    val windDownBlocks: Int get() = max(0, windDownMinutes / Schedule.BLOCK_MINUTES)

    /** The schedule on [day]: [schedule], or the step a sleep shift has got to. */
    fun schedule(day: String): Schedule = sleepShift?.schedule(day, schedule) ?: schedule

    /** The day a moment belongs to (see [Schedule.dayID]), going by the rollover of the date it falls on. */
    fun dayID(at: Instant, zone: ZoneId = ZoneId.systemDefault()): String =
        schedule(DayID.string(at, zone)).dayID(at, zone)

    /** The schedule of the day [at] belongs to. */
    fun schedule(at: Instant, zone: ZoneId = ZoneId.systemDefault()): Schedule = schedule(dayID(at, zone))

    /** These settings without a sleep shift that has got you to [schedule] by [day]. */
    fun endingSleepShiftIfDone(day: String): AppSettings =
        if (sleepShift?.isDone(day, schedule) == true) copy(sleepShift = null) else this

    /** Every activity group as it is now, in order: the built-in ones, then your own. */
    val groups: List<CategoryGroup>
        get() = CategoryGroup.builtIn.map { group -> editedGroups.firstOrNull { it.id == group.id } ?: group } +
            customGroups

    /**
     * Everything a block can be logged as, in every track, with your edits: activities group by group (your own after
     * the built-in ones in each), then postures, then retired activities. The ones you removed stay in place, retired.
     */
    val categories: List<BlockCategory>
        get() {
            val groups = groups
            val edits = editedCategories.associateBy { it.id }
            val removed = removedCategories.toSet()
            val resolve = { category: BlockCategory ->
                resolved(edits[category.id] ?: category, groups).copy(isRemoved = category.id in removed)
            }
            val byGroup = (BlockCategories.activities + customCategories).map(resolve).groupBy { it.group?.id ?: "" }
            return groups.flatMap { byGroup[it.id] ?: emptyList() } + BlockCategories.body.map(resolve) +
                customCategories.filter { it.track != Track.ACTIVITY }.map(resolve) +
                BlockCategories.retired.map(resolve)
        }

    /** Whether [id] is a built-in activity or group the user changed. */
    fun isEdited(id: String): Boolean = editedCategories.any { it.id == id } || editedGroups.any { it.id == id }

    /** With an edited activity saved: your own in place, a built-in one as an edit over the original (or none, when
     *  it's the same as the original). */
    fun saving(category: BlockCategory): AppSettings {
        val custom = customCategories.indexOfFirst { it.id == category.id }
        val original = BlockCategories.defaults.firstOrNull { it.id == category.id }
        val edited = editedCategories.indexOfFirst { it.id == category.id }
        return when {
            custom >= 0 -> copy(customCategories = customCategories.replacing(custom, category))
            original != null && resolved(original, groups) == category -> reset(category.id)
            edited >= 0 -> copy(editedCategories = editedCategories.replacing(edited, category))
            else -> copy(editedCategories = editedCategories + category)
        }
    }

    /** With an edited group saved: your own in place, a built-in one as an edit over the original (or none, when it's
     *  the same as the original). */
    fun saving(group: CategoryGroup): AppSettings {
        val custom = customGroups.indexOfFirst { it.id == group.id }
        val edited = editedGroups.indexOfFirst { it.id == group.id }
        return when {
            custom >= 0 -> copy(customGroups = customGroups.replacing(custom, group))
            group in CategoryGroup.builtIn -> reset(group.id)
            edited >= 0 -> copy(editedGroups = editedGroups.replacing(edited, group))
            else -> copy(editedGroups = editedGroups + group)
        }
    }

    /** Without an activity (or posture) in the palette, search and library. Blocks logged with it keep it, and it
     *  keeps its star for when it's put back. */
    fun removing(id: String): AppSettings =
        if (id in removedCategories) this else copy(removedCategories = removedCategories + id)

    /** With a removed activity back as it was. */
    fun restoring(id: String): AppSettings = copy(removedCategories = removedCategories.filter { it != id })

    /** With a built-in activity or group back the way it came. */
    fun reset(id: String): AppSettings = copy(
        editedCategories = editedCategories.filter { it.id != id }, editedGroups = editedGroups.filter { it.id != id })

    /** The day at [at], drawn from [log] (which should be that day's, see [Schedule.dayID]), with what [timers] have
     *  run so far logged on it. */
    fun snapshot(
        at: Instant, log: DayLog, track: Track? = null, timers: List<LiveTimer> = emptyList(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): DaySnapshot {
        val schedule = schedule(at, zone)
        val live = timers.fold(log) { day, timer -> day.record(timer.session(at), schedule, zone) }
        return DaySnapshot(
            status = DayStatus(schedule, schedule.timelineMinute(at, zone), windDownBlocks),
            logs = live.logs(schedule), categories = categories, favorites = favorites, track = track ?: this.track,
            grid = grid, day = live.day, sessions = live.sessions)
    }

    /** The schedule of a day other than today. A past day keeps the one kept with its logs, or else takes what the
     *  settings make it now; a day still to come always takes what the settings make it, sleep shift and all. */
    fun schedule(of: DayLog, today: String): Schedule =
        if (of.day < today) of.schedule ?: schedule(of.day) else schedule(of.day)

    /** A day other than [today], drawn from its [log]: a past day, where every block has passed, or one still to
     *  come, where none has started. */
    fun snapshot(of: DayLog, today: String, track: Track? = null): DaySnapshot {
        val schedule = schedule(of, today)
        return DaySnapshot(
            status = if (of.day < today) {
                DayStatus.ended(schedule, of.loggedEnd(schedule), windDownBlocks)
            } else {
                DayStatus.ahead(schedule, windDownBlocks)
            },
            logs = of.logs(schedule), categories = categories, favorites = favorites, track = track ?: this.track,
            grid = grid, day = of.day, sessions = of.sessions)
    }

    companion object {
        val standard = AppSettings(schedule = Schedule.standard)

        /** An activity with its group as it is now (renamed or recolored), or in Life when its group is gone. */
        internal fun resolved(category: BlockCategory, groups: List<CategoryGroup>): BlockCategory {
            if (category.track != Track.ACTIVITY) return category
            val id = category.group?.id ?: ""
            return category.withGroup(
                groups.firstOrNull { it.id == id } ?: groups.firstOrNull { it.id == CategoryGroup.life.id })
        }

        private fun <T> List<T>.replacing(index: Int, element: T): List<T> = toMutableList().also { it[index] = element }
    }
}

/** Settings as they're saved, every key but the schedule optional, as settings saved by older versions lack them. */
@Serializable
private class SavedSettings(
    val schedule: Schedule,
    val track: Track? = null,
    val favorites: List<String>? = null,
    val customCategories: List<BlockCategory>? = null,
    val customGroups: List<CategoryGroup>? = null,
    val editedCategories: List<BlockCategory>? = null,
    val editedGroups: List<CategoryGroup>? = null,
    val removedCategories: List<String>? = null,
    val templates: List<Template>? = null,
    val sleepShift: SleepShift? = null,
    val grid: GridMarks? = null,
    val windDownMinutes: Int? = null,
    val notifiesWindDown: Boolean? = null,
    val notifiesBedtime: Boolean? = null,
    val bedtimeNoticeMinutes: Int? = null,
    /** Before favorites, settings kept every category; the user's own carry over. */
    @SerialName("categories") val legacyCategories: List<BlockCategory>? = null,
)

object AppSettingsSerializer : KSerializer<AppSettings> {
    override val descriptor = SavedSettings.serializer().descriptor

    override fun serialize(encoder: Encoder, value: AppSettings) {
        encoder.encodeSerializableValue(
            SavedSettings.serializer(),
            SavedSettings(
                value.schedule, value.track, value.favorites, value.customCategories, value.customGroups,
                value.editedCategories, value.editedGroups, value.removedCategories, value.templates, value.sleepShift,
                value.grid, value.windDownMinutes, value.notifiesWindDown, value.notifiesBedtime,
                value.bedtimeNoticeMinutes))
    }

    override fun deserialize(decoder: Decoder): AppSettings {
        val saved = decoder.decodeSerializableValue(SavedSettings.serializer())
        val standard = AppSettings(saved.schedule)
        val legacy = saved.legacyCategories
        // Edits that match the original aren't edits.
        val editedGroups = (saved.editedGroups ?: emptyList()).filter { it !in CategoryGroup.builtIn }
        var settings = standard.copy(
            track = saved.track ?: standard.track,
            favorites = (saved.favorites ?: standard.favorites) +
                if (legacy != null && saved.favorites == null) legacy.map { it.id }.filter { it.startsWith("custom-") }
                else emptyList(),
            customCategories = saved.customCategories ?: legacy?.filter { it.id.startsWith("custom-") } ?: emptyList(),
            customGroups = saved.customGroups ?: emptyList(),
            editedGroups = editedGroups,
            removedCategories = saved.removedCategories ?: emptyList(),
            templates = saved.templates ?: emptyList(),
            sleepShift = saved.sleepShift,
            grid = saved.grid ?: GridMarks.standard,
            windDownMinutes = saved.windDownMinutes ?: standard.windDownMinutes,
            notifiesWindDown = saved.notifiesWindDown ?: true,
            notifiesBedtime = saved.notifiesBedtime ?: true,
            bedtimeNoticeMinutes = saved.bedtimeNoticeMinutes ?: 0,
        )
        // Activities save only their group's id; put the groups themselves back.
        val groups = settings.groups
        settings = settings.copy(
            customCategories = settings.customCategories.map { AppSettings.resolved(it, groups) },
            editedCategories = (saved.editedCategories ?: emptyList()).map { AppSettings.resolved(it, groups) }
                .filter { edited ->
                    BlockCategories.defaults.firstOrNull { it.id == edited.id }?.let { AppSettings.resolved(it, groups) } !=
                        edited
                })
        return settings
    }
}

/**
 * How the grid marks the time, so a block's time can be read off its place: with wider gaps along each hour row and
 * between the rows, and minute numbers above it.
 */
@Serializable
data class GridMarks(
    /** Minutes between the wider gaps that split each row, 10, 15, 20 or 30, or 0 for none. */
    val gapMinutes: Int = 30,
    /** Minutes between the numbers written above the grid, 10, 15, 20 or 30, or 0 for none. */
    val labelMinutes: Int = 0,
    /** Where wider gaps fall between the hour rows. */
    val hourGaps: HourGaps = HourGaps.NONE,
    /** Hours between the gaps on the clock, counted from midnight. */
    val gapHours: Int = 3,
    /** Parts the waking day is split into. */
    val dayParts: Int = 4,
) {
    @Serializable
    enum class HourGaps {
        @SerialName("none") NONE,

        /** Every [gapHours] hours on the clock, such as 09:00, 12:00 and 15:00. */
        @SerialName("clock") CLOCK,

        /** Between [dayParts] equal parts of the waking day, at the nearest hour. */
        @SerialName("divided") DIVIDED,
    }

    /** The rows out of [rowCount] with a wider gap above them, for a grid laid out by [schedule]. */
    fun rowsAfterGaps(schedule: Schedule, rowCount: Int): Set<Int> {
        val rows = when (hourGaps) {
            HourGaps.NONE -> emptyList()
            HourGaps.CLOCK -> (0 until rowCount).filter { schedule.hour(it) % max(1, gapHours) == 0 }
            HourGaps.DIVIDED -> (1 until max(1, dayParts)).map { part ->
                val slot = schedule.gridOffset + schedule.awakeBlocks * part / dayParts
                (slot.toDouble() / Schedule.BLOCKS_PER_HOUR).roundToInt()
            }
        }
        return rows.filter { it in 1 until rowCount }.toSet()
    }

    /** Blocks between the wider gaps, or null when there are none. */
    val blocksPerGroup: Int? get() = if (gapMinutes > 0) gapMinutes / Schedule.BLOCK_MINUTES else null

    /** The minutes past the hour written above the grid; the hour labels stand for :00. */
    val labeledMinutes: List<Int>
        get() = if (labelMinutes > 0) (labelMinutes until 60 step labelMinutes).toList() else emptyList()

    companion object {
        val standard = GridMarks()
    }
}
