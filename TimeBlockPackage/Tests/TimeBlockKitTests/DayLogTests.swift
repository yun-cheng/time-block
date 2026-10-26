import Foundation
import Testing
@testable import TimeBlockKit

struct DayLogTests {
    let schedule = Schedule.standard

    private func painted(_ steps: [(Range<Int>, String?, Track)]) -> DayLog {
        var log = DayLog(day: "2026-10-24", wakeMinute: schedule.wakeMinute)
        for (range, category, track) in steps {
            log.set(range, to: category, in: track, schedule: schedule)
        }
        return log
    }

    /// The logs in time order (they're kept in the order they're layered in).
    private func summary(_ log: DayLog) -> [String] {
        log.logs.sorted { $0.startIndex < $1.startIndex }.map { "\($0.categoryID) \($0.startIndex)..<\($0.range.upperBound)" + ($0.note.map { " \"\($0)\"" } ?? "") }
    }

    @Test func paintingNextToARunJoinsIt() {
        let log = painted([(0..<3, "work", .activity), (3..<4, "work", .activity), (4..<6, "meal", .activity)])
        #expect(summary(log) == ["work 0..<4", "meal 4..<6"])
    }

    @Test func paintingInsideARunSplitsIt() {
        let log = painted([(0..<10, "work", .activity), (4..<6, "coffee", .activity)])
        #expect(summary(log) == ["work 0..<4", "coffee 4..<6", "work 6..<10"])
    }

    @Test func clearingRemovesOnlyThatTrack() {
        let log = painted([(0..<10, "work", .activity), (0..<10, "sitting", .body), (2..<8, nil, .activity)])
        #expect(Set(summary(log)) == ["work 0..<2", "work 8..<10", "sitting 0..<10"])
    }

    @Test func blocksKeepTheirClockTimeWhenWakeTimeMoves() {
        let log = painted([(12..<14, "meal", .activity)])  // 08:00–08:10 with a 07:00 wake
        let later = Schedule(wakeMinute: 7 * 60 + 30, bedMinute: 23 * 60)
        #expect(log.logs(for: later).map(\.range) == [6..<8])
        #expect(later.clockMinute(ofBlock: 6) == 8 * 60)
    }

    @Test func lateNightStillBelongsToTheDayBefore() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func date(_ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: 30))!
        }
        #expect(schedule.dayID(for: date(25, 1), calendar: calendar) == "2026-10-24")  // 01:30, before the 05:00 rollover
        #expect(schedule.dayID(for: date(25, 6), calendar: calendar) == "2026-10-25")
    }

    @Test func logsSurviveASaveAndLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LogStore(directory: directory)
        let log = painted([(0..<6, "exercise", .activity), (0..<6, "exercising", .body)])
        try store.save(log)
        #expect(store.load(day: log.day, wakeMinute: 0) == log)
        #expect(store.load(day: "2026-10-25", wakeMinute: 420).logs.isEmpty)
    }

    @Test func savedDaysAreListedOldestFirst() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LogStore(directory: directory)
        for day in ["2026-10-25", "2026-09-30", "2026-10-24"] {
            try store.save(DayLog(day: day, wakeMinute: 420))
        }
        try Data().write(to: directory.appending(path: "notes.json"))
        #expect(store.savedDays() == ["2026-09-30", "2026-10-24", "2026-10-25"])
    }

    @Test func aDayKeepsItsScheduleWithItsLogs() throws {
        let log = painted([(0..<3, "work", .activity)])
        #expect(log.schedule == schedule)
        // Days saved before schedules were kept with them have none.
        let old = Data(#"{"day":"2026-10-20","wakeMinute":420,"logs":[]}"#.utf8)
        #expect(try JSONDecoder().decode(DayLog.self, from: old).schedule == nil)
    }

    @Test func aPastDayHasEveryBlockPastAndRunsToItsLastLog() {
        var log = painted([(0..<3, "work", .activity)])
        var settings = AppSettings(schedule: schedule)
        settings.schedule = Schedule(wakeMinute: 8 * 60, bedMinute: 22 * 60)
        // The day keeps the schedule it had, 07:00–23:00, whatever the settings say now.
        var past = settings.snapshot(of: log, today: "2026-10-26")
        #expect(past.status.schedule == schedule)
        #expect(past.cells.count == schedule.awakeBlocks)
        #expect(past.cells.allSatisfy { $0.phase == .past })
        #expect(past.status.currentIndex == nil && past.status.mood == .calm && past.status.overtimeBlocks == 0)
        // Blocks logged past bedtime show as the day's overtime.
        log.set(schedule.awakeBlocks..<(schedule.awakeBlocks + 4), to: "work", in: .activity, schedule: schedule)
        past = settings.snapshot(of: log, today: "2026-10-26")
        #expect(past.cells.count == schedule.awakeBlocks + 4)
        #expect(past.status.overtimeBlocks == 4 && past.pastOvertimeCount == 4)
        #expect(past.status.mood == .calm)
    }

    @Test func aDayAheadHasNoBlockStartedAndFollowsTheSettings() {
        let log = painted([(24..<27, "work", .activity)])  // 2026-10-24 09:00–09:15, logged with a 07:00 wake
        let later = Schedule(wakeMinute: 8 * 60, bedMinute: 22 * 60)
        let ahead = AppSettings(schedule: later).snapshot(of: log, today: "2026-10-23")
        #expect(ahead.status.isAhead && ahead.status.currentIndex == nil && ahead.status.mood == .calm)
        // Still to come, it takes the schedule the settings give it now, and its blocks keep their clock times.
        #expect(ahead.status.schedule == later)
        #expect(ahead.cells.count == later.awakeBlocks)
        #expect(ahead.cells.allSatisfy { $0.phase == .future })
        #expect(ahead.cells.filter { $0.categoryID == "work" }.map(\.index) == [12, 13, 14])
    }

    @Test func unloggedRunReachesBackToTheLastLog() {
        let log = painted([(0..<4, "work", .activity)])
        let snapshot = DaySnapshot(
            status: DayStatus(schedule: schedule, nowMinute: 7 * 60 + 50), logs: log.logs(for: schedule),
            categories: BlockCategory.defaults)
        #expect(snapshot.unloggedRun(before: 10) == 4..<10)
        #expect(snapshot.unloggedRun(before: 4) == 4..<4)
    }

    @Test func runCoversTheWholeStretchOfOneCategory() {
        let log = painted([(0..<4, "work", .activity), (4..<6, "coffee", .activity), (6..<9, "work", .activity)])
        let snapshot = DaySnapshot(
            status: DayStatus(schedule: schedule, nowMinute: 9 * 60), logs: log.logs(for: schedule),
            categories: BlockCategory.defaults)
        #expect(snapshot.run(around: 2) == 0..<4)
        #expect(snapshot.run(around: 5) == 4..<6)
        // 09:00 is block 24: the gap so far (with the block in progress), the empty rest of the day and the time to wind
        // down before bed are apart.
        let windDown = snapshot.status.windDownRange
        #expect(snapshot.run(around: 20) == 9..<25)
        #expect(snapshot.run(around: 30) == 25..<windDown.lowerBound)
        #expect(snapshot.run(around: windDown.lowerBound) == windDown)
    }

    @Test func resizingARunTakesInOrLetsGoOfBlocks() {
        var log = painted([(0..<4, "work", .activity), (6..<8, "coffee", .activity), (0..<10, "sit", .body)])
        log.setNote("deep", for: 0..<4, in: .activity, schedule: schedule)
        // Longer, over what was there.
        log.resize(0..<4, to: 0..<7, in: .activity, schedule: schedule)
        #expect(summary(log) == ["sit 0..<10", "work 0..<7 \"deep\"", "coffee 7..<8"])
        // Shorter from the start, which clears what it lets go.
        log.resize(0..<7, to: 3..<7, in: .activity, schedule: schedule)
        #expect(summary(log) == ["sit 0..<10", "work 3..<7 \"deep\"", "coffee 7..<8"])
        // Not one category: nothing changes.
        log.resize(3..<8, to: 3..<9, in: .activity, schedule: schedule)
        #expect(summary(log) == ["sit 0..<10", "work 3..<7 \"deep\"", "coffee 7..<8"])
    }

    @Test func movingBlocksTakesTheirGapsAndNotesAlong() {
        var log = painted([
            (0..<3, "work", .activity), (4..<6, "coffee", .activity), (6..<12, "meal", .activity), (0..<12, "sit", .body),
        ])
        log.setNote("deep", for: 0..<3, in: .activity, schedule: schedule)
        // Work, a gap and coffee, 6 blocks later: over the meal, leaving the first blocks empty.
        log.move(0..<6, by: 6, in: .activity, schedule: schedule)
        #expect(summary(log) == ["sit 0..<12", "work 6..<9 \"deep\"", "coffee 10..<12"])
        // Back over part of itself.
        log.move(6..<12, by: -2, in: .activity, schedule: schedule)
        #expect(summary(log) == ["sit 0..<12", "work 4..<7 \"deep\"", "coffee 8..<10"])
        // Nothing logged: nothing moves, and nothing is cleared where it would land.
        log.move(0..<4, by: 4, in: .activity, schedule: schedule)
        #expect(summary(log) == ["sit 0..<12", "work 4..<7 \"deep\"", "coffee 8..<10"])
    }

    @Test func rightClickingClearsTheRunOrTheSelectionItIsIn() {
        let log = painted([(0..<4, "work", .activity), (4..<6, "coffee", .activity)])
        let snapshot = DaySnapshot(
            status: DayStatus(schedule: schedule, nowMinute: 9 * 60), logs: log.logs(for: schedule),
            categories: BlockCategory.defaults)
        #expect(snapshot.clearable(at: 2) == 0..<4)
        #expect(snapshot.clearable(at: 2, selection: 3..<8) == 0..<4)
        #expect(snapshot.clearable(at: 5, selection: 3..<8) == 3..<8)
        // Nothing logged to clear.
        #expect(snapshot.clearable(at: 10) == nil)
        #expect(snapshot.clearable(at: 10, selection: 8..<12) == nil)
        #expect(snapshot.clearable(at: -1) == nil)
    }

    @Test func aNoteCoversExactlyTheBlocksItIsWrittenOn() {
        var log = painted([(0..<10, "work", .activity), (0..<10, "sitting", .body)])
        log.setNote("Wrote PLAN.md", for: 2..<5, in: .activity, schedule: schedule)
        #expect(Set(summary(log)) == ["work 0..<2", "work 2..<5 \"Wrote PLAN.md\"", "work 5..<10", "sitting 0..<10"])
        log.setNote("  ", for: 0..<10, in: .activity, schedule: schedule)
        #expect(Set(summary(log)) == ["work 0..<10", "sitting 0..<10"])
    }

    @Test func aRunGivenAnotherCategoryKeepsItsNote() {
        var log = painted([(0..<10, "work", .activity)])
        log.setNote("Standup", for: 2..<4, in: .activity, schedule: schedule)
        log.set(2..<4, to: "meeting", in: .activity, schedule: schedule)
        #expect(summary(log) == ["work 0..<2", "meeting 2..<4 \"Standup\"", "work 4..<10"])
        // Painting over part of it doesn't take the note along.
        log.set(3..<5, to: "coffee", in: .activity, schedule: schedule)
        #expect(summary(log) == ["work 0..<2", "meeting 2..<3 \"Standup\"", "coffee 3..<5", "work 5..<10"])
    }

    @Test func aNoteMakesItsOwnRun() {
        var log = painted([(0..<10, "work", .activity)])
        log.setNote("Review", for: 4..<6, in: .activity, schedule: schedule)
        let snapshot = DaySnapshot(
            status: DayStatus(schedule: schedule, nowMinute: 9 * 60), logs: log.logs(for: schedule),
            categories: BlockCategory.defaults)
        #expect(snapshot.run(around: 1) == 0..<4)
        #expect(snapshot.run(around: 4) == 4..<6)
        #expect(snapshot.cells[5].note == "Review")
    }

    @Test func onlyFavoritesOfTheTrackAreInThePalette() {
        let log = painted([(0..<2, "snack", .activity), (2..<4, "lunch", .activity)])
        let snapshot = DaySnapshot(
            status: DayStatus(schedule: schedule, nowMinute: 9 * 60), logs: log.logs(for: schedule),
            categories: BlockCategory.defaults, favorites: ["lunch", "sitting", "work"])
        // By group, whatever order they were starred in: Work comes before Life.
        #expect(snapshot.favorites.map(\.id) == ["work", "lunch"])
        #expect(snapshot.cells[0].categoryID == "snack")
        // Snack and Lunch are both Life, and are summed up together.
        #expect(snapshot.legendTotals.first.map { [$0.name, "\($0.blocks)"] } == ["Life", "4"])
    }
}
