package dev.timeblock.core

import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ReminderTest {
    /** 07:00–23:00. */
    private val hours = Schedule.standard
    private val zone = ZoneId.systemDefault()

    /** 12:00–12:30, notifying. */
    private val lunch = Template(id = "lunch", categoryID = "lunch", startMinute = 12 * 60, length = 6, notifies = true)

    /** 2026-10-26 is a Monday. */
    private fun monday(steps: DayLog.() -> DayLog = { this }) = DayLog("2026-10-26", hours.wakeMinute).steps()

    private fun at(hour: Int, minute: Int = 0, day: Int = 26) =
        ZonedDateTime.of(2026, 10, day, hour, minute, 0, 0, zone).toInstant()

    private fun settings(templates: List<Template>, windDown: Boolean = false, bedtime: Boolean = false) =
        AppSettings(hours, templates = templates, notifiesWindDown = windDown, notifiesBedtime = bedtime)

    private fun summary(reminders: List<Reminder>) = reminders.map {
        val time = it.date.atZone(zone)
        "${time.hour}:${time.minute} ${it.title}"
    }

    private fun DayLog.plan(templates: List<Template>) = plan(templates, schedule = hours)

    @Test fun routinesThatNotifySayWhenTheyStart() {
        val coffee = Template(id = "coffee", categoryID = "coffee", startMinute = 15 * 60, length = 3)
        val settings = settings(listOf(lunch, coffee))
        val log = monday { plan(listOf(lunch, coffee)) }
        val reminders = settings.reminders(log, at(9))
        assertEquals(listOf("12:0 Lunch"), summary(reminders))
        assertEquals("12:00–12:30, from your routine.", reminders.first().body)
        // Once it's started, there's nothing left to say.
        assertTrue(settings.reminders(log, at(12)).isEmpty())
    }

    @Test fun routinesNotifyWhereTheyreStillPreLogged() {
        val settings = settings(listOf(lunch))
        // A meeting took its first 10 minutes.
        var log = monday { set(60 upTo 62, "meeting", Track.ACTIVITY, hours).plan(listOf(lunch)) }
        val reminders = settings.reminders(log, at(9))
        assertEquals(listOf("12:10 Lunch"), summary(reminders))
        assertEquals("12:10–12:30, from your routine.", reminders.first().body)
        // Logged over, it isn't coming.
        log = log.set(60 upTo 66, "email", Track.ACTIVITY, hours)
        assertTrue(settings.reminders(log, at(9)).isEmpty())
    }

    @Test fun routinesAfterAnActivityNotifyEachTime() {
        val shower = Template(
            id = "shower", categoryID = "shower", anchor = Template.Anchor.AFTER, afterCategoryID = "gym", length = 3,
            notifies = true)
        val log = monday {
            set(96 upTo 108, "gym", Track.ACTIVITY, hours).set(132 upTo 136, "gym", Track.ACTIVITY, hours)
                .plan(listOf(shower))
        }
        val reminders = settings(listOf(shower)).reminders(log, at(9))
        assertEquals(listOf("16:0 Shower", "18:20 Shower"), summary(reminders))
        assertEquals(2, reminders.map { it.id }.toSet().size)
    }

    @Test fun windingDownAndBedtimeNotify() {
        val settings = settings(emptyList(), windDown = true, bedtime = true)
        val reminders = settings.reminders(monday(), at(9))
        assertEquals(
            listOf("22:30 Time to wind down", "23:0 It's bedtime", "23:30 30 minutes past bedtime", "1:0 2 hours past bedtime"),
            summary(reminders))
        // Two hours past an 11pm bedtime is the next morning.
        assertEquals(27, reminders[3].date.atZone(zone).dayOfMonth)
        // Without a wind-down, there's none to say.
        val none = settings.copy(windDownMinutes = 0)
        assertEquals("23:0 It's bedtime", summary(none.reminders(monday(), at(9))).first())
    }

    @Test fun bedtimeCanNotifyAhead() {
        var settings = settings(emptyList(), bedtime = true).copy(bedtimeNoticeMinutes = 15)
        assertEquals(
            listOf("22:45 Bedtime in 15 minutes", "23:30 30 minutes past bedtime", "1:0 2 hours past bedtime"),
            summary(settings.reminders(monday(), at(9))))
        settings = settings.copy(bedtimeNoticeMinutes = 90)
        assertEquals("21:30 Bedtime in 1h 30m", summary(settings.reminders(monday(), at(9))).first())
        // As winding down starts, winding down says it.
        settings = settings.copy(bedtimeNoticeMinutes = 30, notifiesWindDown = true)
        assertEquals(
            listOf("22:30 Time to wind down", "23:30 30 minutes past bedtime"),
            summary(settings.reminders(monday(), at(9))).take(2))
    }

    @Test fun notificationSettingsRoundTrip() {
        val settings = AppSettings.standard.copy(notifiesBedtime = false, bedtimeNoticeMinutes = 20, templates = listOf(lunch))
        val decoded = TimeBlockJson.decodeFromString(
            AppSettings.serializer(), TimeBlockJson.encodeToString(AppSettings.serializer(), settings))
        assertEquals(settings, decoded)
        // Settings saved before notifications notify of winding down and bedtime, and of no routine.
        val old = TimeBlockJson.decodeFromString(
            AppSettings.serializer(),
            """
            {"schedule": {"wakeMinute": 420, "bedMinute": 1380, "rolloverMinute": 300},
             "templates": [{"id": "t", "categoryID": "lunch", "startMinute": 720, "length": 6,
                            "weekdays": [2], "isEnabled": true}]}
            """)
        assertTrue(old.notifiesWindDown && old.notifiesBedtime && old.bedtimeNoticeMinutes == 0)
        assertEquals(false, old.templates.first().notifies)
    }
}
