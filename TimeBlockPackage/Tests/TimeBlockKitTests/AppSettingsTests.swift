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
        #expect(decoded.grid == .standard)
    }

    @Test func gridMarksSplitAndNumberTheMinutes() {
        #expect(GridMarks.standard.blocksPerGroup == 6)
        #expect(GridMarks.standard.labeledMinutes == [])
        #expect(GridMarks(labelMinutes: 30).labeledMinutes == [30])
        #expect(GridMarks(labelMinutes: 15).labeledMinutes == [15, 30, 45])
        #expect(GridMarks(labelMinutes: 10).labeledMinutes == [10, 20, 30, 40, 50])
        #expect(GridMarks(labelMinutes: 20).labeledMinutes == [20, 40])
        #expect(GridMarks(gapMinutes: 0).blocksPerGroup == nil)
        // The numbers don't depend on the gaps.
        #expect(GridMarks(gapMinutes: 30, labelMinutes: 15).labeledMinutes == [15, 30, 45])
    }

    @Test func favoritesAndOwnActivitiesAreSaved() throws {
        var settings = AppSettings.standard
        var reading = BlockCategory.new(in: .activity, name: "Reading club")
        reading.group = .learn
        settings.customCategories = [reading]
        settings.favorites = ["lunch", reading.id]
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        // Your own activities sit with their group, after its built-in ones.
        #expect(decoded.categories.last { $0.group == .learn } == reading)
        #expect(reading.color == CategoryGroup.learn.color)
    }

    @Test func ownGroupsNameAndColorTheirActivities() throws {
        var settings = AppSettings.standard
        var music = CategoryGroup.new(name: "Music", color: RGB(hex: 0x38BDF8))
        settings.customGroups = [music]
        let piano = BlockCategory.new(in: .activity, group: music, name: "Piano")
        settings.customCategories = [piano]
        music.name = "Practice"
        music.color = RGB(hex: 0xD946EF)
        settings.save(music)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.categories == settings.categories)
        #expect(decoded.customGroups == [music])
        let found = try #require(decoded.categories.first { $0.id == piano.id })
        #expect(found.group?.name == "Practice")
        #expect(found.color == music.color)
        // Groups of your own come after the built-in ones.
        #expect(decoded.categories.last { $0.track == .activity && !$0.isRetired }?.id == piano.id)
        // An activity whose group is gone falls back to Life.
        settings.customGroups = []
        #expect(settings.categories.first { $0.id == piano.id }?.group == .life)
    }

    @Test func builtInActivitiesAndGroupsCanBeEditedAndReset() throws {
        var settings = AppSettings.standard
        var lunch = try #require(settings.categories.first { $0.id == "lunch" })
        lunch.name = "Midday meal"
        lunch.group = .people
        settings.save(lunch)
        var people = CategoryGroup.people
        people.name = "Company"
        settings.save(people)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        let edited = try #require(decoded.categories.first { $0.id == "lunch" })
        #expect(edited.name == "Midday meal")
        #expect(edited.group?.name == "Company")
        #expect(edited.color == CategoryGroup.people.color)
        #expect(decoded.isEdited("lunch") && decoded.isEdited("people") && !decoded.isEdited("dinner"))
        settings.reset("lunch")
        settings.reset("people")
        #expect(settings.categories == BlockCategory.defaults)
        // Saving one unchanged, as a text field does when it takes focus, isn't an edit.
        settings.save(try #require(settings.categories.first { $0.id == "dinner" }))
        settings.save(CategoryGroup.life)
        #expect(settings.editedCategories.isEmpty && settings.editedGroups.isEmpty)
        // Nor is one saved that way before.
        settings.editedCategories = [try #require(settings.categories.first { $0.id == "dinner" })]
        let reloaded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(reloaded.editedCategories.isEmpty)
    }

    @Test func removedActivitiesStayKnownAndCanBePutBack() throws {
        var settings = AppSettings.standard
        let piano = BlockCategory.new(in: .activity, name: "Piano")
        settings.customCategories = [piano]
        settings.favorites += [piano.id]
        settings.remove("lunch")
        settings.remove(piano.id)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        // Still known, so blocks logged with them keep their name and color, but retired.
        let lunch = try #require(decoded.categories.first { $0.id == "lunch" })
        #expect(lunch.name == "Lunch" && lunch.isRetired)
        #expect(decoded.categories.first { $0.id == piano.id }?.isRetired == true)
        let snapshot = decoded.snapshot(at: .now, log: DayLog(day: "2026-01-01", wakeMinute: decoded.schedule.wakeMinute))
        #expect(!snapshot.trackCategories.contains { $0.id == "lunch" || $0.id == piano.id })
        #expect(!snapshot.favorites.contains { $0.id == "lunch" || $0.id == piano.id })
        // Put back as it was, starred.
        settings.restore("lunch")
        #expect(settings.categories.first { $0.id == "lunch" }?.isRetired == false)
        let restored = settings.snapshot(at: .now, log: DayLog(day: "2026-01-01", wakeMinute: settings.schedule.wakeMinute))
        #expect(restored.favorites.contains { $0.id == "lunch" })
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
