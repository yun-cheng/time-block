import Foundation
import Testing
@testable import TimeBlockKit

struct TemplateTests {
    let schedule = Schedule.standard
    let calendar = Calendar(identifier: .gregorian)
    /// 12:00–12:30.
    let lunch = Template(id: "lunch", categoryID: "lunch", startMinute: 12 * 60, length: 6)

    /// The logs in time order (they're kept in the order they're layered in).
    private func summary(_ log: DayLog) -> [String] {
        log.logs.sorted { $0.startIndex < $1.startIndex }.map { "\($0.categoryID) \($0.startIndex)..<\($0.range.upperBound) \($0.source)" }
    }

    /// 2026-10-26 is a Monday.
    private func monday(_ steps: (inout DayLog) -> Void = { _ in }) -> DayLog {
        var log = DayLog(day: "2026-10-26", wakeMinute: schedule.wakeMinute)
        steps(&log)
        return log
    }

    @Test func dayKnowsItsWeekday() {
        #expect(monday().weekday(calendar: calendar) == 2)
        #expect(DayLog(day: "2026-10-25", wakeMinute: 0).weekday(calendar: calendar) == 1)
    }

    @Test func templatesLogOnlyTheDaysTheyComeBackOn() {
        let weekend = Template(id: "brunch", categoryID: "breakfast", startMinute: 10 * 60, length: 12, weekdays: Template.weekends)
        let log = monday { $0.plan([lunch, weekend], schedule: schedule, calendar: calendar) }
        #expect(summary(log) == ["lunch 60..<66 template"])
        #expect(log.isPlanned)
    }

    @Test func templatesFillOnlyFreeBlocksInTheirTrack() {
        let log = monday {
            $0.set(62..<64, to: "meeting", in: .activity, schedule: schedule)
            $0.set(60..<66, to: "sitting", in: .body, schedule: schedule)
            $0.plan([lunch], schedule: schedule, calendar: calendar)
        }
        #expect(Set(summary(log)) == [
            "lunch 60..<62 template", "meeting 62..<64 manual", "lunch 64..<66 template", "sitting 60..<66 manual",
        ])
    }

    @Test func pausedAndRetiredTemplatesLogNothing() {
        var paused = lunch
        paused.isEnabled = false
        var retired = lunch
        retired.categoryID = "meal"
        let log = monday { $0.plan([paused, retired], schedule: schedule, calendar: calendar) }
        #expect(log.logs.isEmpty)
    }

    @Test func replanningMovesOnlyWhatsStillToCome() {
        var moved = lunch
        moved.startMinute = 12 * 60 + 15  // 12:15–12:45
        let log = monday {
            $0.plan([lunch], schedule: schedule, calendar: calendar)
            $0.set(65..<66, to: nil, in: .activity, schedule: schedule)
            $0.plan([moved], from: 62, schedule: schedule, calendar: calendar)
        }
        #expect(summary(log) == ["lunch 60..<62 template", "lunch 63..<69 template"])
    }

    @Test func templatesStayInsideTheWakingDay() {
        let late = Template(id: "late", categoryID: "reading", startMinute: 22 * 60 + 45, length: 6)
        let early = Template(id: "early", categoryID: "coffee", startMinute: 6 * 60 + 30, length: 12)
        let log = monday { $0.plan([late, early], schedule: schedule, calendar: calendar) }
        #expect(Set(summary(log)) == ["reading 189..<192 template", "coffee 0..<6 template"])
    }

    @Test func daysSavedBeforeTemplatesAreUnplanned() throws {
        let json = #"{"day":"2026-10-26","wakeMinute":420,"logs":[]}"#
        let log = try JSONDecoder().decode(DayLog.self, from: Data(json.utf8))
        #expect(!log.isPlanned)
        let saved = try JSONDecoder().decode(DayLog.self, from: JSONEncoder().encode(monday { $0.plan([], schedule: schedule) }))
        #expect(saved.isPlanned)
    }

    @Test func settingsKeepTemplates() throws {
        var settings = AppSettings.standard
        settings.templates = [lunch]
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.templates == [lunch])
    }
}
