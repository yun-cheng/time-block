import Foundation
import Testing
@testable import TimeBlockKit

struct DayStatusTests {
    let schedule = Schedule.standard  // 07:00–23:00

    private func status(_ clockMinute: Int) -> DayStatus {
        DayStatus(schedule: schedule, nowMinute: schedule.timelineMinute(clockMinute: clockMinute))
    }

    @Test func sixteenHourDayIs192Blocks() {
        #expect(schedule.awakeBlocks == 192)
    }

    @Test func beforeWakeTheWholeDayIsLeft() {
        let s = status(6 * 60)
        #expect(s.currentIndex == nil)
        #expect(s.blocksLeft == 192)
        #expect(s.blocksUsed == 0)
    }

    @Test func blockInProgressCountsAsLeft() {
        #expect(status(7 * 60).blocksLeft == 192)
        #expect(status(7 * 60 + 4).blocksLeft == 192)
        #expect(status(7 * 60 + 5).blocksLeft == 191)
    }

    @Test func middleOfTheDay() {
        let s = status(15 * 60 + 20)
        #expect(s.currentIndex == 100)
        #expect(s.blocksUsed == 100)
        #expect(s.blocksLeft == 92)
        #expect(s.mood == .calm)
    }

    @Test func lastBlockBeforeBedIsWindDown() {
        let s = status(22 * 60 + 59)
        #expect(s.blocksLeft == 1)
        #expect(s.mood == .windDown)
    }

    @Test func goesNegativeAtBedtime() {
        let s = status(23 * 60)
        #expect(s.blocksLeft == -1)
        #expect(s.overtimeBlocks == 1)
        #expect(s.visibleBlocks == 193)
        #expect(s.mood == .uneasy)
    }

    @Test func pastMidnightStillCountsAsToday() {
        #expect(schedule.timelineMinute(clockMinute: 40) == 24 * 60 + 40)
        let s = status(40)  // 00:40
        #expect(s.blocksLeft == -21)
        #expect(s.mood == .dread)
    }

    @Test func moodThresholds() {
        #expect(Mood(blocksLeft: 7) == .calm)
        #expect(Mood(blocksLeft: 6) == .windDown)
        #expect(Mood(blocksLeft: 1) == .windDown)
        #expect(Mood(blocksLeft: -6) == .uneasy)
        #expect(Mood(blocksLeft: -7) == .dread)
        #expect(Mood(blocksLeft: -24) == .dread)
        #expect(Mood(blocksLeft: -25) == .nightmare)
    }

    @Test func windDownLastsAsLongAsSet() {
        #expect(Mood(blocksLeft: 13, windDownBlocks: 12) == .calm)
        #expect(Mood(blocksLeft: 12, windDownBlocks: 12) == .windDown)
        #expect(Mood(blocksLeft: 1, windDownBlocks: 0) == .calm)
        #expect(Mood(blocksLeft: 0, windDownBlocks: 0) == .uneasy)
        let hour = DayStatus(schedule: schedule, nowMinute: 22 * 60, windDownBlocks: 12)
        #expect(hour.mood == .windDown)
        #expect(hour.windDownRange == 180..<192)
    }

    @Test func windDownBlocksAreMarkedBeforeBedtime() {
        let status = DayStatus(schedule: schedule, nowMinute: 23 * 60 + 10, windDownBlocks: 3)
        let cells = DayGrid.cells(status: status, logs: [])
        #expect(cells.filter(\.isWindDown).map(\.index) == [189, 190, 191])
        #expect(DayStatus(schedule: schedule, nowMinute: 12 * 60, windDownBlocks: 0).windDownRange.isEmpty)
    }

    @Test func windDownIsKeptInSettings() throws {
        var settings = AppSettings(schedule: schedule)
        #expect(settings.windDownMinutes == 30)
        settings.windDownMinutes = 45
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.windDownBlocks == 9)
        var log = DayLog(day: "2026-10-26", wakeMinute: schedule.wakeMinute)
        log.rebase(to: schedule)
        let snapshot = decoded.snapshot(at: .now, log: log)
        #expect(snapshot.status.windDownBlocks == 9)
    }

    @Test func bedtimeAfterMidnight() {
        let late = Schedule(wakeMinute: 9 * 60, bedMinute: 60)
        #expect(late.bedTimelineMinute == 25 * 60)
        #expect(late.awakeBlocks == 192)
    }

    @Test func rowsLineUpWithClockHours() {
        let halfPast = Schedule(wakeMinute: 8 * 60 + 30, bedMinute: 23 * 60)
        #expect(halfPast.gridOffset == 6)
        #expect(halfPast.hour(ofRow: 0) == 8)
        #expect(halfPast.hour(ofRow: 16) == 0)
        #expect(schedule.gridOffset == 0)
    }

    @Test func eachTrackShowsOnlyItsOwnLogs() {
        let now = schedule.timelineMinute(clockMinute: 15 * 60 + 20)
        let activity = SampleDay.snapshot(schedule: schedule, nowMinute: now, track: .activity)
        let body = SampleDay.snapshot(schedule: schedule, nowMinute: now, track: .body)
        // 10:30 is a standup meeting in Activity and standing in Body.
        let standup = schedule.blockIndex(clockMinute: 10 * 60 + 30)
        #expect(activity.cells[standup].categoryID == "meeting")
        #expect(body.cells[standup].categoryID == "standing")
        #expect(body.legendTotals.first?.name == "Sitting")
        #expect(activity.legendTotals.first?.name == "Work")
        // Two unbroken hours of sitting (08:30–10:30 and 13:00–15:00) is the longest so far.
        #expect(body.longestRun(of: "sitting") == 24)
    }

    @Test func gridMarksPhasesAndLogs() {
        let s = status(15 * 60 + 20)  // block 100
        let logs = [BlockLog(startIndex: 98, length: 4, categoryID: "work")]
        let cells = DayGrid.cells(status: s, logs: logs)
        #expect(cells.count == 192)
        #expect(cells[97].phase == .past && cells[97].categoryID == nil)
        #expect(cells[98].phase == .past && cells[98].categoryID == "work")
        #expect(cells[100].phase == .current)
        #expect(cells[101].phase == .future && cells[101].categoryID == "work")
        #expect(cells[102].categoryID == nil)
    }

    @Test func timePickerStepsMoveWholeBlocks() {
        let seven = 7 * 60
        #expect(Schedule.snappedMinute(editing: seven, to: seven + 1) == seven + 5)       // ▲ on minutes
        #expect(Schedule.snappedMinute(editing: seven, to: seven + 59) == seven - 5)      // ▼ wraps :00 to :59
        #expect(Schedule.snappedMinute(editing: seven + 5, to: seven + 4) == seven)       // ▼
        #expect(Schedule.snappedMinute(editing: seven + 55, to: seven + 56) == 8 * 60)    // ▲ past :55
        #expect(Schedule.snappedMinute(editing: seven, to: seven + 60) == 8 * 60)         // hour field
        #expect(Schedule.snappedMinute(editing: seven, to: seven + 32) == seven + 30)     // typed
        #expect(Schedule.snappedMinute(editing: 23 * 60 + 55, to: 23 * 60 + 56) == 0)    // wraps past midnight
        #expect(Schedule.snappedMinute(editing: 0, to: 59) == 23 * 60 + 55)
    }
}
