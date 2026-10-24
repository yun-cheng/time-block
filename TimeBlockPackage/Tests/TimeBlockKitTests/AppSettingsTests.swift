import Foundation
import Testing
@testable import TimeBlockKit

struct AppSettingsTests {
    @Test func widgetTimelineStepsOnBlockBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 15, minute: 22, second: 41))!
        let dates = BlockClock.boundaries(from: date, count: 2, calendar: calendar)
        let minutes = dates.map { calendar.component(.hour, from: $0) * 60 + calendar.component(.minute, from: $0) }
        #expect(minutes == [15 * 60 + 20, 15 * 60 + 25, 15 * 60 + 30])
        #expect(dates.allSatisfy { calendar.component(.second, from: $0) == 0 })
    }

    @Test func settingsRoundTripThroughJSON() throws {
        let settings = AppSettings(schedule: Schedule(wakeMinute: 8 * 60 + 30, bedMinute: 30), track: .body)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }

    @Test func oldSettingsStillLoad() throws {
        let old = #"{"schedule":{"wakeMinute":420,"bedMinute":1380,"rolloverMinute":300},"showsSampleLogs":true}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        #expect(decoded.track == .activity)
        #expect(decoded.schedule == .standard)
    }
}
