package dev.timeblock.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TemplateTest {
    /** 07:00–23:00. */
    private val hours = Schedule.standard
    private val activity = Track.ACTIVITY

    /** 12:00–12:30. */
    private val lunch = Template(id = "lunch", categoryID = "lunch", startMinute = 12 * 60, length = 6)

    /** The logs in time order (they're kept in the order they're layered in). */
    private fun summary(log: DayLog) = log.logs.sortedBy { it.startIndex }.map {
        "${it.categoryID} ${it.range} ${it.source.name.lowercase()}"
    }

    /** 2026-10-26 is a Monday. */
    private fun monday(steps: DayLog.() -> DayLog = { this }) = DayLog("2026-10-26", hours.wakeMinute).steps()

    private fun DayLog.set(range: Span, to: String?, track: Track = activity) = set(range, to, track, hours)
    private fun DayLog.plan(templates: List<Template>, from: Int = 0) = plan(templates, from, hours)
    private fun DayLog.follow(templates: List<Template>, from: Int, before: DayLog) =
        follow(templates, from, before, hours)

    @Test fun dayKnowsItsWeekday() {
        assertEquals(2, monday().weekday)
        assertEquals(1, DayLog("2026-10-25", 0).weekday)
    }

    @Test fun templatesLogOnlyTheDaysTheyComeBackOn() {
        val weekend = Template(
            id = "brunch", categoryID = "breakfast", startMinute = 10 * 60, length = 12, weekdays = Template.weekends)
        val log = monday { plan(listOf(lunch, weekend)) }
        assertEquals(listOf("lunch 60..<66 template"), summary(log))
        assertTrue(log.isPlanned)
    }

    @Test fun templatesFillOnlyFreeBlocksInTheirTrack() {
        val log = monday { set(62 upTo 64, "meeting").set(60 upTo 66, "sitting", Track.BODY).plan(listOf(lunch)) }
        assertEquals(
            setOf("lunch 60..<62 template", "meeting 62..<64 manual", "lunch 64..<66 template", "sitting 60..<66 manual"),
            summary(log).toSet())
    }

    @Test fun pausedAndRetiredTemplatesLogNothing() {
        val log = monday { plan(listOf(lunch.copy(isEnabled = false), lunch.copy(categoryID = "meal"))) }
        assertTrue(log.logs.isEmpty())
    }

    @Test fun replanningMovesOnlyWhatsStillToCome() {
        val moved = lunch.copy(startMinute = 12 * 60 + 15) // 12:15–12:45
        val log = monday { plan(listOf(lunch)).set(65 upTo 66, null).plan(listOf(moved), from = 62) }
        assertEquals(listOf("lunch 60..<62 template", "lunch 63..<69 template"), summary(log))
    }

    @Test fun preLoggedBlocksKnowTheirTemplate() {
        // Two lunches back to back stay two, each its own template's.
        val late = Template(id = "late-lunch", categoryID = "lunch", startMinute = 12 * 60 + 30, length = 6)
        val log = monday { plan(listOf(lunch, late)) }
        assertEquals(listOf("lunch", "late-lunch"), log.logs.sortedBy { it.startIndex }.map { it.templateID })
        assertEquals(listOf(60 upTo 66, 66 upTo 72), log.logs.map { it.range }.sortedBy { it.lowerBound })
    }

    @Test fun templatesStayInsideTheWakingDay() {
        val late = Template(id = "late", categoryID = "reading", startMinute = 22 * 60 + 45, length = 6)
        val early = Template(id = "early", categoryID = "coffee", startMinute = 6 * 60 + 30, length = 12)
        val log = monday { plan(listOf(late, early)) }
        assertEquals(setOf("reading 189..<192 template", "coffee 0..<6 template"), summary(log).toSet())
    }

    @Test fun templatesCanStartAfterWakingOrBeforeBed() {
        // 07:00–23:00: breakfast 30 minutes after waking, reading 45 minutes before bed for half an hour.
        val breakfast = Template(
            id = "breakfast", categoryID = "breakfast", anchor = Template.Anchor.WAKE, offset = 30, length = 6)
        val reading = Template(id = "reading", categoryID = "reading", anchor = Template.Anchor.BED, offset = 45, length = 6)
        val log = monday { plan(listOf(breakfast, reading)) }
        assertEquals(setOf("breakfast 6..<12 template", "reading 183..<189 template"), summary(log).toSet())
        assertEquals(7 * 60 + 30, breakfast.startMinute(hours))
        assertEquals(22 * 60 + 15, reading.startMinute(hours))
    }

    @Test fun relativeTemplatesFollowTheDaysTimes() {
        // Up at 09:00 and to bed at 01:00, past midnight.
        val late = Schedule(wakeMinute = 9 * 60, bedMinute = 60)
        val breakfast = Template(
            id = "breakfast", categoryID = "breakfast", anchor = Template.Anchor.WAKE, offset = 30, length = 6)
        val reading = Template(id = "reading", categoryID = "reading", anchor = Template.Anchor.BED, offset = 90, length = 6)
        assertEquals(6 upTo 12, breakfast.range(late))
        assertEquals(174 upTo 180, reading.range(late))
        assertEquals(23 * 60 + 30, reading.startMinute(late))
    }

    @Test fun reanchoringStartsHalfAnHourFromWakingOrBed() {
        var lunch = lunch.anchored(Template.Anchor.WAKE, schedule = hours)
        assertEquals(30, lunch.offset)
        assertEquals(6 upTo 12, lunch.range(hours))
        lunch = lunch.copy(offset = 60).anchored(Template.Anchor.BED, schedule = hours)
        assertEquals(30, lunch.offset)
        assertEquals(186 upTo 192, lunch.range(hours))
        // Back to a clock time, it starts where it does today: 30 minutes before a 23:30 bedtime.
        lunch = lunch.anchored(Template.Anchor.CLOCK, schedule = Schedule(wakeMinute = 8 * 60, bedMinute = 23 * 60 + 30))
        assertEquals(23 * 60, lunch.startMinute)
    }

    @Test fun templatesCanStartAfterAnActivity() {
        // 15 minutes after lunch's 12:30 end, then a coffee right after that walk, laid out in that order whatever order
        // they're in.
        val walk = Template(
            id = "walk", categoryID = "walk", anchor = Template.Anchor.AFTER, afterCategoryID = "lunch", offset = 15,
            length = 4)
        val coffee = Template(
            id = "coffee", categoryID = "coffee", anchor = Template.Anchor.AFTER, afterCategoryID = "walk", length = 2)
        val log = monday { plan(listOf(coffee, walk, lunch)) }
        assertEquals(listOf("lunch 60..<66 template", "walk 69..<73 template", "coffee 73..<75 template"), summary(log))
        assertEquals(listOf(66), log.ends(walk))
        assertEquals(12 * 60 + 45, walk.startMinute(hours, following = 66))
    }

    private val shower = Template(
        id = "shower", categoryID = "shower", anchor = Template.Anchor.AFTER, afterCategoryID = "gym", length = 3)

    @Test fun templatesFollowAnActivityYouLog() {
        // Each time: the gym at 15:00, then again at 18:00.
        val log = monday { set(96 upTo 108, "gym").set(132 upTo 136, "gym").plan(listOf(shower)) }
        assertEquals(
            listOf("gym 96..<108 manual", "shower 108..<111 template", "gym 132..<136 manual", "shower 136..<139 template"),
            summary(log))
        // Not logged, nothing to follow.
        assertTrue(summary(monday { plan(listOf(shower)) }).isEmpty())
        // Following each other round, with neither there, neither is.
        val gym = Template(
            id = "gym", categoryID = "gym", anchor = Template.Anchor.AFTER, afterCategoryID = "shower", length = 12)
        assertTrue(summary(monday { plan(listOf(gym, shower)) }).isEmpty())
    }

    @Test fun templatesMoveWithTheActivityTheyFollow() {
        var log = monday { plan(listOf(shower)) }
        fun change(from: Int = 100, edit: DayLog.() -> DayLog) {
            val before = log
            log = log.edit().follow(listOf(shower), from, before)
        }
        change { set(96 upTo 108, "gym") }
        assertEquals(listOf("gym 96..<108 manual", "shower 108..<111 template"), summary(log))
        // A longer gym moves it on.
        change { set(108 upTo 114, "gym") }
        assertEquals(listOf("gym 96..<114 manual", "shower 114..<117 template"), summary(log))
        // Cleared, it stays cleared while the gym stays put.
        change { set(114 upTo 117, null) }
        change { set(150 upTo 152, "coffee") }
        assertFalse(summary(log).any { it.startsWith("shower") })
        // Another gym, earlier, gets one of its own; the one cleared after the first stays cleared.
        change(from = 80) { set(80 upTo 84, "gym") }
        assertEquals(listOf("shower 84..<87 template"), summary(log).filter { it.startsWith("shower") })
        // With the gym gone, so is what's still to come of it; blocks already past keep theirs.
        change(from = 86) { set(80 upTo 84, null).set(96 upTo 114, null) }
        assertEquals(listOf("shower 84..<86 template", "coffee 150..<152 manual"), summary(log))
    }

    @Test fun reanchoringAfterAnActivityStartsAsItEnds() {
        var shower = Template(id = "shower", categoryID = "shower", startMinute = 15 * 60, length = 3)
            .anchored(Template.Anchor.AFTER, "gym", hours)
        assertEquals(0, shower.offset)
        assertEquals(108 upTo 111, shower.range(hours, following = 108))
        assertTrue(shower.range(hours).isEmpty)
        // Another to follow keeps how long after.
        shower = shower.copy(offset = 15).anchored(Template.Anchor.AFTER, "run", hours)
        assertEquals("run", shower.afterCategoryID)
        assertEquals(15, shower.offset)
        // Back to a clock time, it starts where it does today: 15 minutes after a run ending at 16:00.
        shower = shower.anchored(Template.Anchor.CLOCK, schedule = hours, following = 108)
        assertEquals(16 * 60 + 15, shower.startMinute)
        assertNull(shower.afterCategoryID)
    }

    @Test fun templatesSavedBeforeAnchorsStartAtAClockTime() {
        val json = """{"id":"lunch","categoryID":"lunch","startMinute":720,"length":6,"weekdays":[2],"isEnabled":true}"""
        val template = TimeBlockJson.decodeFromString(Template.serializer(), json)
        assertEquals(Template.Anchor.CLOCK, template.anchor)
        assertEquals(60 upTo 66, template.range(hours))
        val reading = Template(id = "reading", categoryID = "reading", anchor = Template.Anchor.BED, offset = 45, length = 6)
        assertEquals(reading, roundTrip(reading))
        val walk = Template(
            id = "walk", categoryID = "walk", anchor = Template.Anchor.AFTER, afterCategoryID = "lunch", offset = 15,
            length = 4)
        assertEquals(walk, roundTrip(walk))
    }

    private fun roundTrip(template: Template) = TimeBlockJson.decodeFromString(
        Template.serializer(), TimeBlockJson.encodeToString(Template.serializer(), template))

    @Test fun daysSavedBeforeTemplatesAreUnplanned() {
        val json = """{"day":"2026-10-26","wakeMinute":420,"logs":[]}"""
        assertFalse(TimeBlockJson.decodeFromString(DayLog.serializer(), json).isPlanned)
        val planned = TimeBlockJson.encodeToString(DayLog.serializer(), monday { plan(emptyList()) })
        assertTrue(TimeBlockJson.decodeFromString(DayLog.serializer(), planned).isPlanned)
    }

    @Test fun settingsKeepTemplates() {
        val settings = AppSettings.standard.copy(templates = listOf(lunch))
        val decoded = TimeBlockJson.decodeFromString(
            AppSettings.serializer(), TimeBlockJson.encodeToString(AppSettings.serializer(), settings))
        assertEquals(listOf(lunch), decoded.templates)
    }
}
