package dev.timeblock.core

import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AppSettingsTest {
    private fun roundTrip(settings: AppSettings) = TimeBlockJson.decodeFromString(
        AppSettings.serializer(), TimeBlockJson.encodeToString(AppSettings.serializer(), settings))

    private fun decode(json: String) = TimeBlockJson.decodeFromString(AppSettings.serializer(), json)

    @Test fun widgetTimelineStepsOnBlockBoundaries() {
        val utc = ZoneId.of("UTC")
        val dates = BlockClock.boundaries(ZonedDateTime.of(2026, 10, 24, 15, 22, 41, 0, utc).toInstant(), 2, utc)
        val times = dates.map { it.atZone(utc) }
        assertEquals(listOf(15 * 60 + 20, 15 * 60 + 25, 15 * 60 + 30), times.map { it.hour * 60 + it.minute })
        assertTrue(times.all { it.second == 0 })
    }

    @Test fun settingsRoundTripThroughJSON() {
        val settings = AppSettings(Schedule(wakeMinute = 8 * 60 + 30, bedMinute = 30), track = Track.BODY)
        assertEquals(settings, roundTrip(settings))
    }

    @Test fun oldSettingsStillLoad() {
        val decoded = decode("""{"schedule":{"wakeMinute":420,"bedMinute":1380,"rolloverMinute":300},"showsSampleLogs":true}""")
        assertEquals(Track.ACTIVITY, decoded.track)
        assertEquals(Schedule.standard, decoded.schedule)
        assertEquals(BlockCategories.defaults, decoded.categories)
        assertEquals(GridMarks.standard, decoded.grid)
    }

    @Test fun gridMarksSplitAndNumberTheMinutes() {
        assertEquals(6, GridMarks.standard.blocksPerGroup)
        assertEquals(emptyList(), GridMarks.standard.labeledMinutes)
        assertEquals(listOf(30), GridMarks(labelMinutes = 30).labeledMinutes)
        assertEquals(listOf(15, 30, 45), GridMarks(labelMinutes = 15).labeledMinutes)
        assertEquals(listOf(10, 20, 30, 40, 50), GridMarks(labelMinutes = 10).labeledMinutes)
        assertEquals(listOf(20, 40), GridMarks(labelMinutes = 20).labeledMinutes)
        assertNull(GridMarks(gapMinutes = 0).blocksPerGroup)
        // The numbers don't depend on the gaps.
        assertEquals(listOf(15, 30, 45), GridMarks(gapMinutes = 30, labelMinutes = 15).labeledMinutes)
    }

    @Test fun hourGapsFallOnTheClockOrDivideTheDay() {
        // 07:00–23:00: rows 0 to 15 are 07 to 22.
        val clock = GridMarks(hourGaps = GridMarks.HourGaps.CLOCK, gapHours = 3)
        assertEquals(setOf(2, 5, 8, 11, 14), clock.rowsAfterGaps(Schedule.standard, 16))
        val divided = GridMarks(hourGaps = GridMarks.HourGaps.DIVIDED, dayParts = 4)
        assertEquals(setOf(4, 8, 12), divided.rowsAfterGaps(Schedule.standard, 16))
        // Halfway through 08:30–23:00 is 15:45, so the gap goes above 16:00.
        val late = Schedule(wakeMinute = 8 * 60 + 30, bedMinute = 23 * 60)
        assertEquals(setOf(8), GridMarks(hourGaps = GridMarks.HourGaps.DIVIDED, dayParts = 2).rowsAfterGaps(late, 15))
        assertTrue(GridMarks().rowsAfterGaps(Schedule.standard, 16).isEmpty())
        // Grid settings saved before hour gaps still load.
        assertEquals(GridMarks(gapMinutes = 15), TimeBlockJson.decodeFromString(GridMarks.serializer(), """{"gapMinutes":15}"""))
    }

    @Test fun favoritesAndOwnActivitiesAreSaved() {
        val reading = BlockCategory.new(Track.ACTIVITY, name = "Reading club").withGroup(CategoryGroup.learn)
        val settings = AppSettings.standard.copy(customCategories = listOf(reading), favorites = listOf("lunch", reading.id))
        val decoded = roundTrip(settings)
        assertEquals(settings, decoded)
        // Your own activities sit with their group, after its built-in ones.
        assertEquals(reading, decoded.categories.last { it.group == CategoryGroup.learn })
        assertEquals(CategoryGroup.learn.color, reading.color)
    }

    @Test fun ownGroupsNameAndColorTheirActivities() {
        var music = CategoryGroup.new(RGB.hex(0x38BDF8), name = "Music")
        val piano = BlockCategory.new(Track.ACTIVITY, music, name = "Piano")
        var settings = AppSettings.standard.copy(customGroups = listOf(music), customCategories = listOf(piano))
        music = music.copy(name = "Practice", color = RGB.hex(0xD946EF))
        settings = settings.saving(music)
        val decoded = roundTrip(settings)
        assertEquals(settings.categories, decoded.categories)
        assertEquals(listOf(music), decoded.customGroups)
        val found = decoded.categories.first { it.id == piano.id }
        assertEquals("Practice", found.group?.name)
        assertEquals(music.color, found.color)
        // Groups of your own come after the built-in ones.
        assertEquals(piano.id, decoded.categories.last { it.track == Track.ACTIVITY && !it.isRetired }.id)
        // An activity whose group is gone falls back to Life.
        assertEquals(CategoryGroup.life, settings.copy(customGroups = emptyList()).categories.first { it.id == piano.id }.group)
    }

    @Test fun builtInActivitiesAndGroupsCanBeEditedAndReset() {
        var settings = AppSettings.standard
        val lunch = settings.categories.first { it.id == "lunch" }.copy(name = "Midday meal").withGroup(CategoryGroup.people)
        settings = settings.saving(lunch).saving(CategoryGroup.people.copy(name = "Company"))
        val decoded = roundTrip(settings)
        val edited = decoded.categories.first { it.id == "lunch" }
        assertEquals("Midday meal", edited.name)
        assertEquals("Company", edited.group?.name)
        assertEquals(CategoryGroup.people.color, edited.color)
        assertTrue(decoded.isEdited("lunch") && decoded.isEdited("people") && !decoded.isEdited("dinner"))
        settings = settings.reset("lunch").reset("people")
        assertEquals(BlockCategories.defaults, settings.categories)
        // Saving one unchanged, as a text field does when it takes focus, isn't an edit.
        settings = settings.saving(settings.categories.first { it.id == "dinner" }).saving(CategoryGroup.life)
        assertTrue(settings.editedCategories.isEmpty() && settings.editedGroups.isEmpty())
        // Nor is one saved that way before.
        settings = settings.copy(editedCategories = listOf(settings.categories.first { it.id == "dinner" }))
        assertTrue(roundTrip(settings).editedCategories.isEmpty())
    }

    @Test fun removedActivitiesStayKnownAndCanBePutBack() {
        val piano = BlockCategory.new(Track.ACTIVITY, name = "Piano")
        var settings = AppSettings.standard.let {
            it.copy(customCategories = listOf(piano), favorites = it.favorites + piano.id)
        }.removing("lunch").removing(piano.id)
        val decoded = roundTrip(settings)
        // Still known, so blocks logged with them keep their name and color, but retired.
        val lunch = decoded.categories.first { it.id == "lunch" }
        assertTrue(lunch.name == "Lunch" && lunch.isRetired)
        assertEquals(true, decoded.categories.firstOrNull { it.id == piano.id }?.isRetired)
        val snapshot = decoded.snapshot(Instant.now(), DayLog("2026-01-01", decoded.schedule.wakeMinute))
        assertFalse(snapshot.trackCategories.any { it.id == "lunch" || it.id == piano.id })
        assertFalse(snapshot.favorites.any { it.id == "lunch" || it.id == piano.id })
        // Put back as it was, starred.
        settings = settings.restoring("lunch")
        assertEquals(false, settings.categories.firstOrNull { it.id == "lunch" }?.isRetired)
        val restored = settings.snapshot(Instant.now(), DayLog("2026-01-01", settings.schedule.wakeMinute))
        assertTrue(restored.favorites.any { it.id == "lunch" })
    }

    @Test fun categoriesSavedBeforeFavoritesCarryOver() {
        val decoded = decode(
            """
            {"schedule":{"wakeMinute":420,"bedMinute":1380,"rolloverMinute":300},"track":"activity","categories":[
              {"id":"work","name":"Work","track":"activity","group":"focus","color":{"r":0,"g":0,"b":1},"symbol":"laptopcomputer","isHidden":false},
              {"id":"custom-1","name":"Piano","track":"activity","group":"recharge","color":{"r":1,"g":1,"b":0},"symbol":"pianokeys","isHidden":false}]}
            """)
        assertEquals(listOf("Piano"), decoded.customCategories.map { it.name })
        assertEquals(CategoryGroup.leisure, decoded.customCategories.first().group)
        assertEquals(BlockCategories.defaultFavorites + "custom-1", decoded.favorites)
    }
}
