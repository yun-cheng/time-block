package dev.timeblock.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * The JSON the Swift and Kotlin apps both read, in `fixtures/` at the top of the repository: `swift/` as the Apple app
 * writes it and `kotlin/` as this one does. Each app's tests read both, so either app reads the other's days, settings
 * and timers. The same values are made in TimeBlockKit's `FixtureTests`. Run the tests with `-PwriteFixtures` to write
 * `kotlin/` again after changing what's saved.
 */
class FixtureTest {
    private val directory = File(System.getProperty("fixtures"))
    private val pretty = Json(TimeBlockJson) { prettyPrint = true }

    @Test fun dayReadsAsBothAppsWriteIt() = check(Fixtures.day, DayLog.serializer(), "day.json")

    @Test fun settingsReadAsBothAppsWriteThem() = check(Fixtures.settings, AppSettings.serializer(), "settings.json")

    @Test fun timersReadAsBothAppsWriteThem() =
        check(Fixtures.timers, ListSerializer(LiveTimer.serializer()), "timers.json")

    private fun <T> check(value: T, serializer: KSerializer<T>, name: String) {
        val own = File(directory, "kotlin/$name")
        if (System.getProperty("writeFixtures") != null) {
            own.parentFile.mkdirs()
            own.writeText(pretty.encodeToString(serializer, value) + "\n")
        }
        // What's there is what this app writes now.
        assertEquals(
            TimeBlockJson.parseToJsonElement(own.readText()),
            TimeBlockJson.parseToJsonElement(TimeBlockJson.encodeToString(serializer, value)), "kotlin/$name")
        for (app in listOf("swift", "kotlin")) {
            assertEquals(value, TimeBlockJson.decodeFromString(serializer, File(directory, "$app/$name").readText()), "$app/$name")
        }
    }
}

/** One of most of what's saved, nothing left at its default. */
private object Fixtures {
    fun id(n: Int) = "00000000-0000-0000-0000-%012d".format(n)

    val day = DayLog(
        day = "2026-10-26", wakeMinute = 420, schedule = Schedule.standard,
        logs = listOf(
            BlockLog(id(1), startIndex = 0, length = 24, categoryID = "sitting"),
            BlockLog(id(2), startIndex = 12, length = 6, categoryID = "work"),
            BlockLog(id(3), startIndex = 14, length = 2, categoryID = "email", note = "Inbox zero"),
            BlockLog(id(4), startIndex = 36, length = 6, categoryID = "meeting", note = "Standup", source = BlockLog.Source.CALENDAR),
            BlockLog(
                id(5), startIndex = 60, length = 6, categoryID = "lunch", source = BlockLog.Source.TEMPLATE,
                templateID = "lunch"),
        ),
        isPlanned = true,
        sessions = listOf(
            TimerSession("coding", AppleDateSerializer.instant(783_100_800.25), AppleDateSerializer.instant(783_102_630.75)),
        ),
    )

    val settings: AppSettings = run {
        val music = CategoryGroup("group-music", "Music", RGB.hex(0x38BDF8))
        var settings = AppSettings(
            schedule = Schedule(wakeMinute = 450, bedMinute = 30), track = Track.BODY,
            favorites = listOf("work", "lunch", "custom-piano"),
            customCategories = listOf(
                BlockCategory.activity("custom-piano", "Piano", music, "pianokeys", listOf("keys")),
            ),
            customGroups = listOf(music), removedCategories = listOf("doomscroll"),
            templates = listOf(
                Template(
                    id = "lunch", categoryID = "lunch", startMinute = 750, length = 6, weekdays = Template.weekdaysOnly,
                    notifies = true),
                Template(
                    id = "breakfast", categoryID = "breakfast", anchor = Template.Anchor.WAKE, offset = 30, length = 4,
                    weekdays = setOf(1)),
                Template(
                    id = "reading", categoryID = "reading", anchor = Template.Anchor.BED, offset = 45, length = 6,
                    isEnabled = false),
                Template(
                    id = "shower", categoryID = "shower", anchor = Template.Anchor.AFTER, afterCategoryID = "gym",
                    offset = 15, length = 3),
            ),
            sleepShift = SleepShift(
                Schedule(wakeMinute = 540, bedMinute = 60), "2026-10-24", stepMinutes = 15, everyDays = 2,
                leads = Schedule.End.WAKE, isByFinishDay = true),
            grid = GridMarks(gapMinutes = 15, labelMinutes = 30, hourGaps = GridMarks.HourGaps.DIVIDED, gapHours = 6, dayParts = 3),
            windDownMinutes = 45, notifiesWindDown = false, notifiesBedtime = true, bedtimeNoticeMinutes = 20,
        )
        settings = settings.saving(CategoryGroup.people.copy(name = "Company"))
        val lunch = settings.categories.first { it.id == "lunch" }.copy(name = "Midday meal")
            .withGroup(settings.groups.first { it.id == "people" })
        settings.saving(lunch)
    }

    val timers = listOf(
        LiveTimer(id(10), "writing", countdown = 25 * 60.0, startedAt = AppleDateSerializer.instant(783_110_000.5)),
        LiveTimer(id(11), "coding", startedAt = AppleDateSerializer.instant(783_111_000.0)),
    )
}
