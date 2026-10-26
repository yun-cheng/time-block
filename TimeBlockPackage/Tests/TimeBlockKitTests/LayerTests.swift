import Foundation
import Testing
@testable import TimeBlockKit

/// Several activities in one block at once.
struct LayerTests {
    let schedule = Schedule.standard

    private func log(_ steps: (inout DayLog, Schedule) -> Void) -> DayLog {
        var log = DayLog(day: "2026-10-24", wakeMinute: schedule.wakeMinute)
        steps(&log, schedule)
        return log
    }

    private func snapshot(_ log: DayLog) -> DaySnapshot {
        DaySnapshot(
            status: DayStatus(schedule: schedule, nowMinute: 12 * 60), logs: log.logs(for: schedule),
            categories: BlockCategory.defaults)
    }

    @Test func anAddedActivityGoesOnTopOfWhatTheBlocksHold() {
        let cells = snapshot(log {
            $0.set(0..<10, to: "work", in: .activity, schedule: $1)
            $0.toggle("email", in: 4..<6, schedule: $1)
        }).cells
        #expect(cells[3].categoryIDs == ["work"])
        #expect(cells[4].categoryIDs == ["work", "email"])
        #expect(cells[5].categoryID == "email")
        #expect(cells[6].categoryIDs == ["work"])
    }

    @Test func theRunUnderneathStaysWhole() {
        let log = log {
            $0.set(0..<10, to: "work", in: .activity, schedule: $1)
            $0.toggle("email", in: 4..<6, schedule: $1)
        }
        #expect(log.logs.map(\.range) == [0..<10, 4..<6])
    }

    @Test func addingWhatEveryBlockHoldsTakesItOff() {
        let cells = snapshot(log {
            $0.set(0..<10, to: "work", in: .activity, schedule: $1)
            $0.toggle("email", in: 4..<6, schedule: $1)
            $0.toggle("email", in: 4..<6, schedule: $1)
            // Taking off the one underneath leaves the rest.
            $0.toggle("email", in: 2..<4, schedule: $1)
            $0.toggle("work", in: 0..<10, schedule: $1)
        }).cells
        #expect(cells[1].categoryIDs == [])
        #expect(cells[2].categoryIDs == ["email"])
        #expect(cells[4].categoryIDs == [])
    }

    @Test func addingWhatSomeBlocksHoldSpreadsItAndPutsItOnTop() {
        let log = log {
            $0.toggle("email", in: 4..<6, schedule: $1)
            $0.toggle("work", in: 0..<10, schedule: $1)
            $0.toggle("email", in: 2..<6, schedule: $1)
        }
        #expect(log.logs.map { "\($0.categoryID) \($0.range)" } == ["work 0..<10", "email 2..<6"])
        #expect(snapshot(log).cells[4].categoryIDs == ["work", "email"])
    }

    @Test func aClickedActivityReplacesEveryLayer() {
        let cells = snapshot(log {
            $0.set(0..<10, to: "work", in: .activity, schedule: $1)
            $0.toggle("email", in: 4..<6, schedule: $1)
            $0.set(3..<7, to: "lunch", in: .activity, schedule: $1)
        }).cells
        #expect(cells[2].categoryIDs == ["work"])
        #expect((3..<7).allSatisfy { cells[$0].categoryIDs == ["lunch"] })
        #expect(cells[7].categoryIDs == ["work"])
    }

    @Test func aRunIsBlocksHoldingTheSameActivities() {
        let snapshot = snapshot(log {
            $0.set(0..<10, to: "work", in: .activity, schedule: $1)
            $0.toggle("email", in: 4..<6, schedule: $1)
        })
        #expect(snapshot.run(around: 1) == 0..<4)
        #expect(snapshot.run(around: 5) == 4..<6)
        #expect(snapshot.run(around: 8) == 6..<10)
    }

    @Test func eachActivityCountsItsFullTime() {
        let snapshot = snapshot(log {
            $0.set(0..<12, to: "work", in: .activity, schedule: $1)
            $0.toggle("lunch", in: 6..<12, schedule: $1)
            // Two of one group in a block count once for it.
            $0.toggle("meeting", in: 0..<6, schedule: $1)
        })
        #expect(snapshot.legendTotals.map { "\($0.name) \($0.blocks)" } == ["Work 12", "Life 6"])
        #expect(snapshot.loggedCount == 12)
        #expect(snapshot.longestRun(of: "work") == 12)
    }

    @Test func movingTakesEveryLayerAlong() {
        let cells = snapshot(log {
            $0.set(0..<4, to: "work", in: .activity, schedule: $1)
            $0.toggle("email", in: 2..<4, schedule: $1)
            $0.move(0..<4, by: 10, in: .activity, schedule: $1)
        }).cells
        #expect(cells[0].categoryIDs == [])
        #expect(cells[10].categoryIDs == ["work"])
        #expect(cells[12].categoryIDs == ["work", "email"])
    }

    @Test func layersKeepTheirOrderThroughASaveAndLoad() throws {
        // Even in every way, the one logged last is on top.
        let log = log {
            $0.toggle("email", in: 4..<6, schedule: $1)
            $0.toggle("work", in: 4..<6, schedule: $1)
        }
        let loaded = try JSONDecoder().decode(DayLog.self, from: JSONEncoder().encode(log))
        #expect(snapshot(loaded).cells[4].categoryIDs == ["email", "work"])
    }

    // MARK: What's on top

    @Test func theShortStretchGoesOnTopWhateverWasLoggedFirst() {
        // A trip to the toilet in a morning of work, logged before the work.
        let cells = snapshot(log {
            $0.toggle("bathroom", in: 18..<19, schedule: $1)
            $0.toggle("work", in: 12..<48, schedule: $1)
        }).cells
        #expect(cells[18].categoryIDs == ["work", "bathroom"])
    }

    @Test func dinnerSitsOnAnEveningOfTV() {
        let cells = snapshot(log {
            $0.toggle("dinner", in: 6..<15, schedule: $1)
            $0.toggle("shows", in: 0..<30, schedule: $1)
        }).cells
        #expect((6..<15).allSatisfy { cells[$0].categoryIDs == ["shows", "dinner"] })
    }

    @Test func ofStretchesAsLongTheOneStartingLaterBrokeIn() {
        let cells = snapshot(log {
            $0.toggle("email", in: 3..<9, schedule: $1)
            $0.toggle("work", in: 0..<6, schedule: $1)
        }).cells
        #expect(cells[4].categoryIDs == ["work", "email"])
    }

    @Test func twoActivitiesKeepOneOrderInEveryBlockTheyShare() {
        // Lunch is shorter than Social as a whole, though Social is shorter where they meet.
        let cells = snapshot(log {
            $0.toggle("social", in: 4..<14, schedule: $1)
            $0.toggle("lunch", in: 0..<6, schedule: $1)
        }).cells
        #expect(cells[4].categoryIDs == ["social", "lunch"])
        #expect(cells[5].categoryIDs == ["social", "lunch"])
    }
}
