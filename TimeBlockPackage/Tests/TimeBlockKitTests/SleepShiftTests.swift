import Foundation
import Testing
@testable import TimeBlockKit

struct SleepShiftTests {
    let calendar = Calendar(identifier: .gregorian)
    /// 09:00–01:00, heading to 07:00–23:00.
    let late = Schedule(wakeMinute: 9 * 60, bedMinute: 60)
    let target = Schedule.standard

    private func bedtimes(_ shift: SleepShift, days: ClosedRange<Int>) -> [String] {
        days.map { offset in
            let day = DayID.adding(offset, to: "2026-10-26", calendar: calendar)!
            let schedule = shift.schedule(on: day, target: target, calendar: calendar)
            return String(format: "%02d:%02d", schedule.bedMinute / 60, schedule.bedMinute % 60)
        }
    }

    private func schedule(_ shift: SleepShift, _ offset: Int) -> Schedule {
        shift.schedule(on: DayID.adding(offset, to: "2026-10-26", calendar: calendar)!, target: target, calendar: calendar)
    }

    @Test func bedtimeStepsOverMidnightToTheTarget() {
        let shift = SleepShift(from: late, startDay: "2026-10-26")
        #expect(bedtimes(shift, days: -1...4) == ["01:00", "00:30", "00:00", "23:30", "23:00", "23:00"])
        #expect(shift.stepCount(to: target) == 4)
        // The last step is Thursday night; Friday morning is on 07:00 too.
        #expect(shift.finishDay(target: target, calendar: calendar) == "2026-10-30")
        #expect(!shift.isDone(on: "2026-10-29", target: target, calendar: calendar))
        #expect(shift.isDone(on: "2026-10-30", target: target, calendar: calendar))
    }

    @Test func wakeTimeFollowsTheNextMorningSoEveryNightIsAsLong() {
        let shift = SleepShift(from: late, startDay: "2026-10-26")
        // The first day keeps its morning and takes the first step at night.
        #expect(schedule(shift, 0) == Schedule(wakeMinute: 9 * 60, bedMinute: 30))
        #expect(schedule(shift, 1) == Schedule(wakeMinute: 8 * 60 + 30, bedMinute: 0))
        for offset in 0...5 {
            let night = (schedule(shift, offset).wakeMinute - schedule(shift, offset - 1).bedMinute + 24 * 60) % (24 * 60)
            #expect(night == 8 * 60)
        }
        // The rollover follows wake time, so 05:30 Tuesday is still Monday night.
        #expect(schedule(shift, 1).rolloverMinute == 6 * 60 + 30)
    }

    @Test func aFixedWakeTimeStaysPut() {
        let shift = SleepShift(from: Schedule(wakeMinute: 7 * 60, bedMinute: 60), startDay: "2026-10-26", stepMinutes: 60)
        let schedules = (0...2).map { schedule(shift, $0) }
        #expect(schedules.map(\.wakeMinute) == [420, 420, 420])
        #expect(schedules.map(\.bedMinute) == [0, 23 * 60, 23 * 60])
        #expect(shift.finishDay(target: target, calendar: calendar) == "2026-10-27")
    }

    @Test func aWakeTimeShiftMovesNoMorningOnItsFirstDay() {
        let shift = SleepShift(from: Schedule(wakeMinute: 9 * 60, bedMinute: 23 * 60), startDay: "2026-10-26", stepMinutes: 60)
        #expect((0...3).map { schedule(shift, $0).wakeMinute } == [540, 480, 420, 420])
        #expect(shift.finishDay(target: target, calendar: calendar) == "2026-10-28")
    }

    @Test func stepsCanBeDaysApartAndLater() {
        let early = Schedule(wakeMinute: 6 * 60, bedMinute: 22 * 60)
        let shift = SleepShift(from: early, startDay: "2026-10-26", stepMinutes: 45, everyDays: 2)
        #expect(bedtimes(shift, days: 0...4) == ["22:45", "22:45", "23:00", "23:00", "23:00"])
        #expect(shift.finishDay(target: target, calendar: calendar) == "2026-10-29")
    }

    @Test func settingsUseEachDaysSchedule() throws {
        var settings = AppSettings(schedule: target, sleepShift: SleepShift(from: late, startDay: "2026-10-26"))
        #expect(settings.schedule(on: "2026-10-25", calendar: calendar) == late)
        #expect(settings.schedule(on: "2026-10-27", calendar: calendar).bedMinute == 0)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        settings.sleepShift = nil
        #expect(settings.schedule(on: "2026-10-27", calendar: calendar) == target)
    }

    @Test func aMomentBelongsToTheDayItsDatesRolloverSays() {
        let settings = AppSettings(schedule: target, sleepShift: SleepShift(from: late, startDay: "2026-10-26"))
        let at = { (day: Int, hour: Int, minute: Int) in
            self.calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }
        // Tuesday's rollover is 06:30 (wake 08:30), so 06:00 Tuesday is still Monday night.
        #expect(settings.dayID(for: at(27, 6, 0), calendar: calendar) == "2026-10-26")
        #expect(settings.dayID(for: at(27, 6, 30), calendar: calendar) == "2026-10-27")
        #expect(settings.schedule(for: at(26, 12, 0), calendar: calendar).bedMinute == 30)
    }

    @Test func aShiftCanBeSetToFinishByADay() {
        let shift = SleepShift(from: late, finishingOn: "2026-10-31", target: target, everyDays: 2, calendar: calendar)
        #expect(shift.startDay == "2026-10-24")
        #expect(shift.finishDay(target: target, calendar: calendar) == "2026-10-31")
        let oneStep = SleepShift(from: late, finishingOn: "2026-10-31", target: target, stepMinutes: 120, calendar: calendar)
        #expect(oneStep.startDay == "2026-10-30")
    }

    @Test func eitherEndCanLeadAndTheOtherFollowOrStay() {
        #expect(late.moving(.bed, to: 23 * 60, keepsSleep: true) == target)
        #expect(late.moving(.wake, to: 7 * 60, keepsSleep: true) == target)
        #expect(late.moving(.wake, to: 7 * 60, keepsSleep: false) == Schedule(wakeMinute: 7 * 60, bedMinute: 60))
        #expect(late.moving(.bed, to: 23 * 60, keepsSleep: false) == Schedule(wakeMinute: 9 * 60, bedMinute: 23 * 60))
    }

    @Test func distanceTakesTheShortWayRound() {
        #expect(SleepShift.distance(from: 60, to: 23 * 60) == -120)
        #expect(SleepShift.distance(from: 23 * 60, to: 60) == 120)
        #expect(SleepShift.distance(from: 7 * 60, to: 7 * 60) == 0)
    }
}
