import Foundation
import Testing
@testable import TimeBlockKit

struct ReminderTests {
    let schedule = Schedule.standard
    let calendar = Calendar(identifier: .gregorian)
    /// 12:00–12:30, notifying.
    let lunch = Template(id: "lunch", categoryID: "lunch", startMinute: 12 * 60, length: 6, notifies: true)

    /// 2026-10-26 is a Monday.
    private func monday(_ steps: (inout DayLog) -> Void = { _ in }) -> DayLog {
        var log = DayLog(day: "2026-10-26", wakeMinute: schedule.wakeMinute)
        steps(&log)
        return log
    }

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 26) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func settings(_ templates: [Template], windDown: Bool = false, bedtime: Bool = false) -> AppSettings {
        AppSettings(schedule: schedule, templates: templates, notifiesWindDown: windDown, notifiesBedtime: bedtime)
    }

    private func summary(_ reminders: [Reminder]) -> [String] {
        reminders.map {
            "\(calendar.component(.hour, from: $0.date)):\(calendar.component(.minute, from: $0.date)) \($0.title)"
        }
    }

    @Test func routinesThatNotifySayWhenTheyStart() {
        let coffee = Template(id: "coffee", categoryID: "coffee", startMinute: 15 * 60, length: 3)
        let settings = settings([lunch, coffee])
        let log = monday { $0.plan([lunch, coffee], schedule: schedule, calendar: calendar) }
        let reminders = settings.reminders(for: log, after: at(9), calendar: calendar)
        #expect(summary(reminders) == ["12:0 Lunch"])
        #expect(reminders.first?.body == "12:00–12:30, from your routine.")
        // Once it's started, there's nothing left to say.
        #expect(settings.reminders(for: log, after: at(12), calendar: calendar).isEmpty)
    }

    @Test func routinesNotifyWhereTheyreStillPreLogged() {
        let settings = settings([lunch])
        // A meeting took its first 10 minutes.
        var log = monday {
            $0.set(60..<62, to: "meeting", in: .activity, schedule: schedule)
            $0.plan([lunch], schedule: schedule, calendar: calendar)
        }
        let reminders = settings.reminders(for: log, after: at(9), calendar: calendar)
        #expect(summary(reminders) == ["12:10 Lunch"])
        #expect(reminders.first?.body == "12:10–12:30, from your routine.")
        // Logged over, it isn't coming.
        log.set(60..<66, to: "email", in: .activity, schedule: schedule)
        #expect(settings.reminders(for: log, after: at(9), calendar: calendar).isEmpty)
    }

    @Test func routinesAfterAnActivityNotifyEachTime() {
        let shower = Template(
            id: "shower", categoryID: "shower", anchor: .after, afterCategoryID: "gym", length: 3, notifies: true)
        let log = monday {
            $0.set(96..<108, to: "gym", in: .activity, schedule: schedule)
            $0.set(132..<136, to: "gym", in: .activity, schedule: schedule)
            $0.plan([shower], schedule: schedule, calendar: calendar)
        }
        let reminders = settings([shower]).reminders(for: log, after: at(9), calendar: calendar)
        #expect(summary(reminders) == ["16:0 Shower", "18:20 Shower"])
        #expect(Set(reminders.map(\.id)).count == 2)
    }

    @Test func windingDownAndBedtimeNotify() {
        let settings = settings([], windDown: true, bedtime: true)
        let reminders = settings.reminders(for: monday(), after: at(9), calendar: calendar)
        #expect(summary(reminders) == [
            "22:30 Time to wind down", "23:0 It's bedtime", "23:30 30 minutes past bedtime", "1:0 2 hours past bedtime",
        ])
        // Two hours past an 11pm bedtime is the next morning.
        #expect(calendar.component(.day, from: reminders[3].date) == 27)
        // Without a wind-down, there's none to say.
        var none = settings
        none.windDownMinutes = 0
        #expect(summary(none.reminders(for: monday(), after: at(9), calendar: calendar)).first == "23:0 It's bedtime")
    }

    @Test func bedtimeCanNotifyAhead() {
        var settings = settings([], bedtime: true)
        settings.bedtimeNoticeMinutes = 15
        let reminders = settings.reminders(for: monday(), after: at(9), calendar: calendar)
        #expect(summary(reminders) == [
            "22:45 Bedtime in 15 minutes", "23:30 30 minutes past bedtime", "1:0 2 hours past bedtime",
        ])
        settings.bedtimeNoticeMinutes = 90
        #expect(summary(settings.reminders(for: monday(), after: at(9), calendar: calendar)).first
            == "21:30 Bedtime in 1h 30m")
        // As winding down starts, winding down says it.
        settings.bedtimeNoticeMinutes = 30
        settings.notifiesWindDown = true
        #expect(summary(settings.reminders(for: monday(), after: at(9), calendar: calendar)).prefix(2)
            == ["22:30 Time to wind down", "23:30 30 minutes past bedtime"])
    }

    @Test func notificationSettingsRoundTrip() throws {
        var settings = AppSettings.standard
        settings.notifiesBedtime = false
        settings.bedtimeNoticeMinutes = 20
        settings.templates = [lunch]
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        // Settings saved before notifications notify of winding down and bedtime, and of no routine.
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("""
            {"schedule": {"wakeMinute": 420, "bedMinute": 1380, "rolloverMinute": 300},
             "templates": [{"id": "t", "categoryID": "lunch", "startMinute": 720, "length": 6,
                            "weekdays": [2], "isEnabled": true}]}
            """.utf8))
        #expect(old.notifiesWindDown && old.notifiesBedtime && old.bedtimeNoticeMinutes == 0)
        #expect(old.templates.first?.notifies == false)
    }
}
