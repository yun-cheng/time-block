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

    @Test func preLoggedBlocksKnowTheirTemplate() {
        // Two lunches back to back stay two, each its own template's.
        let late = Template(id: "late-lunch", categoryID: "lunch", startMinute: 12 * 60 + 30, length: 6)
        let log = monday { $0.plan([lunch, late], schedule: schedule, calendar: calendar) }
        #expect(log.logs.sorted { $0.startIndex < $1.startIndex }.map(\.templateID) == ["lunch", "late-lunch"])
        #expect(log.logs.map(\.range).sorted { $0.lowerBound < $1.lowerBound } == [60..<66, 66..<72])
    }

    @Test func templatesStayInsideTheWakingDay() {
        let late = Template(id: "late", categoryID: "reading", startMinute: 22 * 60 + 45, length: 6)
        let early = Template(id: "early", categoryID: "coffee", startMinute: 6 * 60 + 30, length: 12)
        let log = monday { $0.plan([late, early], schedule: schedule, calendar: calendar) }
        #expect(Set(summary(log)) == ["reading 189..<192 template", "coffee 0..<6 template"])
    }

    @Test func templatesCanStartAfterWakingOrBeforeBed() {
        // 07:00–23:00: breakfast 30 minutes after waking, reading 45 minutes before bed for half an hour.
        let breakfast = Template(id: "breakfast", categoryID: "breakfast", anchor: .wake, offset: 30, length: 6)
        let reading = Template(id: "reading", categoryID: "reading", anchor: .bed, offset: 45, length: 6)
        let log = monday { $0.plan([breakfast, reading], schedule: schedule, calendar: calendar) }
        #expect(Set(summary(log)) == ["breakfast 6..<12 template", "reading 183..<189 template"])
        #expect(breakfast.startMinute(in: schedule) == 7 * 60 + 30)
        #expect(reading.startMinute(in: schedule) == 22 * 60 + 15)
    }

    @Test func relativeTemplatesFollowTheDaysTimes() {
        // Up at 09:00 and to bed at 01:00, past midnight.
        let late = Schedule(wakeMinute: 9 * 60, bedMinute: 60)
        let breakfast = Template(id: "breakfast", categoryID: "breakfast", anchor: .wake, offset: 30, length: 6)
        let reading = Template(id: "reading", categoryID: "reading", anchor: .bed, offset: 90, length: 6)
        #expect(breakfast.range(in: late) == 6..<12)
        #expect(reading.range(in: late) == 174..<180)
        #expect(reading.startMinute(in: late) == 23 * 60 + 30)
    }

    @Test func reanchoringStartsHalfAnHourFromWakingOrBed() {
        var lunch = lunch
        lunch.anchor(to: .wake, in: schedule)
        #expect(lunch.offset == 30)
        #expect(lunch.range(in: schedule) == 6..<12)
        lunch.offset = 60
        lunch.anchor(to: .bed, in: schedule)
        #expect(lunch.offset == 30)
        #expect(lunch.range(in: schedule) == 186..<192)
        // Back to a clock time, it starts where it does today: 30 minutes before a 23:30 bedtime.
        lunch.anchor(to: .clock, in: Schedule(wakeMinute: 8 * 60, bedMinute: 23 * 60 + 30))
        #expect(lunch.startMinute == 23 * 60)
    }

    @Test func templatesCanStartAfterAnActivity() {
        // 15 minutes after lunch's 12:30 end, then a coffee right after that walk, laid out in that order whatever
        // order they're in.
        let walk = Template(id: "walk", categoryID: "walk", anchor: .after, afterCategoryID: "lunch", offset: 15, length: 4)
        let coffee = Template(id: "coffee", categoryID: "coffee", anchor: .after, afterCategoryID: "walk", length: 2)
        let log = monday { $0.plan([coffee, walk, lunch], schedule: schedule, calendar: calendar) }
        #expect(summary(log) == ["lunch 60..<66 template", "walk 69..<73 template", "coffee 73..<75 template"])
        #expect(log.ends(of: walk) == [66])
        #expect(walk.startMinute(in: schedule, following: 66) == 12 * 60 + 45)
    }

    @Test func templatesFollowAnActivityYouLog() {
        let shower = Template(id: "shower", categoryID: "shower", anchor: .after, afterCategoryID: "gym", length: 3)
        // Each time: the gym at 15:00, then again at 18:00.
        let log = monday {
            $0.set(96..<108, to: "gym", in: .activity, schedule: schedule)
            $0.set(132..<136, to: "gym", in: .activity, schedule: schedule)
            $0.plan([shower], schedule: schedule, calendar: calendar)
        }
        #expect(summary(log) == [
            "gym 96..<108 manual", "shower 108..<111 template", "gym 132..<136 manual", "shower 136..<139 template",
        ])
        // Not logged, nothing to follow.
        #expect(summary(monday { $0.plan([shower], schedule: schedule, calendar: calendar) }).isEmpty)
        // Following each other round, with neither there, neither is.
        let gym = Template(id: "gym", categoryID: "gym", anchor: .after, afterCategoryID: "shower", length: 12)
        #expect(summary(monday { $0.plan([gym, shower], schedule: schedule, calendar: calendar) }).isEmpty)
    }

    @Test func templatesMoveWithTheActivityTheyFollow() {
        let shower = Template(id: "shower", categoryID: "shower", anchor: .after, afterCategoryID: "gym", length: 3)
        var log = monday { $0.plan([shower], schedule: schedule, calendar: calendar) }
        func change(_ edit: (inout DayLog) -> Void) {
            let before = log
            edit(&log)
            log.follow([shower], from: 100, after: before, schedule: schedule, calendar: calendar)
        }
        change { $0.set(96..<108, to: "gym", in: .activity, schedule: schedule) }
        #expect(summary(log) == ["gym 96..<108 manual", "shower 108..<111 template"])
        // A longer gym moves it on.
        change { $0.set(108..<114, to: "gym", in: .activity, schedule: schedule) }
        #expect(summary(log) == ["gym 96..<114 manual", "shower 114..<117 template"])
        // Cleared, it stays cleared while the gym stays put.
        change { $0.set(114..<117, to: nil, in: .activity, schedule: schedule) }
        change { $0.set(150..<152, to: "coffee", in: .activity, schedule: schedule) }
        #expect(!summary(log).contains { $0.hasPrefix("shower") })
        // Another gym, earlier, gets one of its own; the one cleared after the first stays cleared.
        var before = log
        log.set(80..<84, to: "gym", in: .activity, schedule: schedule)
        log.follow([shower], from: 80, after: before, schedule: schedule, calendar: calendar)
        #expect(summary(log).filter { $0.hasPrefix("shower") } == ["shower 84..<87 template"])
        // With the gym gone, so is what's still to come of it; blocks already past keep theirs.
        before = log
        log.set(80..<84, to: nil, in: .activity, schedule: schedule)
        log.set(96..<114, to: nil, in: .activity, schedule: schedule)
        log.follow([shower], from: 86, after: before, schedule: schedule, calendar: calendar)
        #expect(summary(log) == ["shower 84..<86 template", "coffee 150..<152 manual"])
    }

    @Test func reanchoringAfterAnActivityStartsAsItEnds() {
        var shower = Template(id: "shower", categoryID: "shower", startMinute: 15 * 60, length: 3)
        shower.anchor(to: .after, after: "gym", in: schedule)
        #expect(shower.offset == 0)
        #expect(shower.range(in: schedule, following: 108) == 108..<111)
        #expect(shower.range(in: schedule).isEmpty)
        shower.offset = 15
        // Another to follow keeps how long after.
        shower.anchor(to: .after, after: "run", in: schedule)
        #expect(shower.afterCategoryID == "run")
        #expect(shower.offset == 15)
        // Back to a clock time, it starts where it does today: 15 minutes after a run ending at 16:00.
        shower.anchor(to: .clock, in: schedule, following: 108)
        #expect(shower.startMinute == 16 * 60 + 15)
        #expect(shower.afterCategoryID == nil)
    }

    @Test func templatesSavedBeforeAnchorsStartAtAClockTime() throws {
        let json = #"{"id":"lunch","categoryID":"lunch","startMinute":720,"length":6,"weekdays":[2],"isEnabled":true}"#
        let template = try JSONDecoder().decode(Template.self, from: Data(json.utf8))
        #expect(template.anchor == .clock)
        #expect(template.range(in: schedule) == 60..<66)
        let reading = Template(id: "reading", categoryID: "reading", anchor: .bed, offset: 45, length: 6)
        #expect(try JSONDecoder().decode(Template.self, from: JSONEncoder().encode(reading)) == reading)
        let walk = Template(id: "walk", categoryID: "walk", anchor: .after, afterCategoryID: "lunch", offset: 15, length: 4)
        #expect(try JSONDecoder().decode(Template.self, from: JSONEncoder().encode(walk)) == walk)
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
