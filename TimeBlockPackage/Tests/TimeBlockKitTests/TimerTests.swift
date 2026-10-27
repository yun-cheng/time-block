import Foundation
import Testing
@testable import TimeBlockKit

/// Timers logging activities live.
struct TimerTests {
    let schedule = Schedule.standard
    let day = "2026-10-24"
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    /// `clock` ("10:03:30") on the day.
    private func at(_ clock: String, dayOffset: Int = 0) -> Date {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        let noon = DayID.date(day, calendar: calendar)!
        let date = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: noon))!
        return date.addingTimeInterval(Double(parts[0] * 3600 + parts[1] * 60 + (parts.count > 2 ? parts[2] : 0)))
    }

    /// The block of the day starting at `clock` ("10:05").
    private func block(_ clock: String) -> Int {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        return schedule.blockIndex(clockMinute: parts[0] * 60 + parts[1])
    }

    private func session(_ from: String, _ to: String, _ categoryID: String = "coding") -> TimerSession {
        TimerSession(categoryID: categoryID, start: at(from), end: at(to))
    }

    @Test func aStretchTakesEveryBlockItTouches() {
        #expect(session("10:03", "10:31").blocks(on: day, schedule: schedule, calendar: calendar)
            == block("10:00")..<block("10:35"))
    }

    @Test func aStretchKeepsItsClockTimesOnDaysTheClocksChange() {
        // The clocks went forward an hour at 01:00 on 2026-03-29.
        let clock = { (hour: Int, minute: Int) in
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: hour, minute: minute))!
        }
        let session = TimerSession(categoryID: "coding", start: clock(10, 0), end: clock(10, 30))
        #expect(session.blocks(on: "2026-03-29", schedule: schedule, calendar: calendar)
            == block("10:00")..<block("10:30"))
    }

    @Test func aStretchEndingOnABoundaryStopsThere() {
        #expect(session("10:00", "10:30").blocks(on: day, schedule: schedule, calendar: calendar)
            == block("10:00")..<block("10:30"))
    }

    @Test func aMomentTakesItsBlock() {
        #expect(session("10:03:10", "10:03:40").blocks(on: day, schedule: schedule, calendar: calendar)
            == block("10:00")..<block("10:05"))
    }

    @Test func timeBeforeWakeAndOnOtherDaysIsLeftOut() {
        #expect(session("06:40", "07:12").blocks(on: day, schedule: schedule, calendar: calendar) == 0..<block("07:15"))
        #expect(session("10:00", "11:00").blocks(on: "2026-10-25", schedule: schedule, calendar: calendar).isEmpty)
    }

    @Test func aStretchPastMidnightStaysWithTheNightBefore() {
        let late = TimerSession(categoryID: "shows", start: at("23:50"), end: at("00:20", dayOffset: 1))
        #expect(late.blocks(on: day, schedule: schedule, calendar: calendar) == block("23:50")..<block("00:20"))
    }

    @Test func aCountdownGoesOnPastZero() {
        let timer = LiveTimer(categoryID: "writing", countdown: 25 * 60, startedAt: at("09:00"))
        #expect(timer.remaining(at: at("09:10")) == 900)
        #expect(timer.zeroDate == at("09:25"))
        #expect(timer.remaining(at: at("09:27")) == -120)
        #expect(LiveTimer(categoryID: "coding", startedAt: at("09:00")).remaining(at: at("09:10")) == nil)
    }

    @Test func aRecordedStretchStacksOnWhatTheBlocksHold() {
        var log = DayLog(day: day, wakeMinute: schedule.wakeMinute)
        log.set(block("10:00")..<block("11:00"), to: "meeting", in: .activity, schedule: schedule)
        log.record(session("10:20", "10:31", "bathroom"), schedule: schedule, calendar: calendar)
        let cells = DayGrid.cells(status: DayStatus(schedule: schedule, nowMinute: 12 * 60), logs: log.logs)
        #expect(cells[block("10:15")].categoryIDs == ["meeting"])
        #expect(cells[block("10:20")].categoryIDs == ["meeting", "bathroom"])
        #expect(cells[block("10:30")].categoryIDs == ["meeting", "bathroom"])
        #expect(cells[block("10:35")].categoryIDs == ["meeting"])
        #expect(log.sessions == [session("10:20", "10:31", "bathroom")])
    }

    @Test func blocksHoldingTheActivityAlreadyKeepIt() {
        var log = DayLog(day: day, wakeMinute: schedule.wakeMinute)
        log.set(block("10:00")..<block("10:10"), to: "coding", in: .activity, schedule: schedule)
        log.setNote("Parser", for: block("10:00")..<block("10:10"), in: .activity, schedule: schedule)
        log.record(session("10:05", "10:22"), schedule: schedule, calendar: calendar)
        #expect(log.logs.map(\.range) == [block("10:00")..<block("10:10"), block("10:10")..<block("10:25")])
        #expect(log.logs.first?.note == "Parser")
    }

    @Test func aRunningTimerShowsUpToTheBlockInProgress() {
        let settings = AppSettings.standard
        let log = DayLog(day: day, wakeMinute: schedule.wakeMinute)
        let timer = LiveTimer(categoryID: "coding", startedAt: at("10:03"))
        let snapshot = settings.snapshot(at: at("10:16"), log: log, timers: [timer], calendar: calendar)
        #expect(snapshot.cells[block("10:00")..<block("10:20")].allSatisfy { $0.categoryID == "coding" })
        #expect(snapshot.cells[block("10:20")].categoryID == nil)
        #expect(snapshot.sessions(of: ["coding"], in: block("10:10")..<block("10:15"), calendar: calendar)
            == [TimerSession(categoryID: "coding", start: at("10:03"), end: at("10:16"))])
    }

    @Test func aCountdownTakesEveryBlockItTouches() {
        #expect(CountdownLength.blocks(20) == 4)
        #expect(CountdownLength.blocks(21) == 5)
        #expect(CountdownLength.blocks(1) == 1)
    }

    @Test func countdownLengthsShowInHoursAndMinutes() {
        #expect(CountdownLength.text(30) == "30 min")
        #expect(CountdownLength.text(60) == "1 h")
        #expect(CountdownLength.text(90) == "1 h 30 min")
    }

    @Test func daysSavedBeforeTimersStillLoad() throws {
        let json = #"{"day":"2026-10-24","wakeMinute":420,"logs":[]}"#
        let log = try JSONDecoder().decode(DayLog.self, from: Data(json.utf8))
        #expect(log.sessions.isEmpty)
    }
}
