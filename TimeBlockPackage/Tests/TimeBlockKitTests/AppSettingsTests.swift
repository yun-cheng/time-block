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
        #expect(decoded.categories == BlockCategory.defaults)
    }

    @Test func favoritesAndOwnActivitiesAreSaved() throws {
        var settings = AppSettings.standard
        var reading = BlockCategory.new(in: .activity, name: "Reading club")
        reading.group = .learn
        settings.customCategories = [reading]
        settings.favorites = ["lunch", reading.id]
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        #expect(decoded.categories.last == reading)
        #expect(reading.color == CategoryGroup.learn.color)
    }

    @Test func categoriesSavedBeforeFavoritesCarryOver() throws {
        let old = #"""
        {"schedule":{"wakeMinute":420,"bedMinute":1380,"rolloverMinute":300},"track":"activity","categories":[
          {"id":"work","name":"Work","track":"activity","group":"focus","color":{"r":0,"g":0,"b":1},"symbol":"laptopcomputer","isHidden":false},
          {"id":"custom-1","name":"Piano","track":"activity","group":"recharge","color":{"r":1,"g":1,"b":0},"symbol":"pianokeys","isHidden":false}]}
        """#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        #expect(decoded.customCategories.map(\.name) == ["Piano"])
        #expect(decoded.customCategories.first?.group == .leisure)
        #expect(decoded.favorites == BlockCategory.defaultFavorites + ["custom-1"])
    }
}
