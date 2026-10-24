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

    private func summary(_ log: DayLog) -> [String] {
        log.logs.map { "\($0.categoryID) \($0.startIndex)..<\($0.range.upperBound)" }
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
        // 09:00 is block 24: the gap so far (with the block in progress) and the empty rest of the day are apart.
        #expect(snapshot.run(around: 20) == 9..<25)
        #expect(snapshot.run(around: 30) == 25..<schedule.awakeBlocks)
    }
}
