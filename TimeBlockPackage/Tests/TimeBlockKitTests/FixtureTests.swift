import Foundation
import Testing
@testable import TimeBlockKit

/// The JSON the Swift and Kotlin apps both read, in `fixtures/` at the top of the repository: `swift/` as this app
/// writes it and `kotlin/` as the Android one does. Each app's tests read both, so either app reads the other's days,
/// settings and timers. The same values are made in the Kotlin core's `FixtureTest`. Run the tests with
/// `WRITE_FIXTURES=1` to write `swift/` again after changing what's saved.
struct FixtureTests {
    private static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "fixtures")

    @Test func dayReadsAsBothAppsWriteIt() throws {
        try check(Fixtures.day, "day.json")
    }

    @Test func settingsReadAsBothAppsWriteThem() throws {
        try check(Fixtures.settings, "settings.json")
    }

    @Test func timersReadAsBothAppsWriteThem() throws {
        try check(Fixtures.timers, "timers.json")
    }

    private func check<Value: Codable & Equatable>(_ value: Value, _ name: String) throws {
        let own = Self.directory.appending(path: "swift/\(name)")
        if ProcessInfo.processInfo.environment["WRITE_FIXTURES"] != nil {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try FileManager.default.createDirectory(
                at: own.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(value).write(to: own)
        }
        for app in ["swift", "kotlin"] {
            let data = try Data(contentsOf: Self.directory.appending(path: "\(app)/\(name)"))
            #expect(try JSONDecoder().decode(Value.self, from: data) == value, "\(app)/\(name)")
        }
    }
}

/// One of most of what's saved, nothing left at its default.
private enum Fixtures {
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    static let day = DayLog(
        day: "2026-10-26", wakeMinute: 420, schedule: .standard,
        logs: [
            BlockLog(id: id(1), startIndex: 0, length: 24, categoryID: "sitting"),
            BlockLog(id: id(2), startIndex: 12, length: 6, categoryID: "work"),
            BlockLog(id: id(3), startIndex: 14, length: 2, categoryID: "email", note: "Inbox zero"),
            BlockLog(id: id(4), startIndex: 36, length: 6, categoryID: "meeting", note: "Standup", source: .calendar),
            BlockLog(id: id(5), startIndex: 60, length: 6, categoryID: "lunch", source: .template, templateID: "lunch"),
        ],
        isPlanned: true,
        sessions: [
            TimerSession(
                categoryID: "coding", start: Date(timeIntervalSinceReferenceDate: 783_100_800.25),
                end: Date(timeIntervalSinceReferenceDate: 783_102_630.75)),
        ])

    static let settings: AppSettings = {
        let music = CategoryGroup(id: "group-music", name: "Music", color: RGB(hex: 0x38BDF8))
        var settings = AppSettings(
            schedule: Schedule(wakeMinute: 450, bedMinute: 30), track: .body,
            favorites: ["work", "lunch", "custom-piano"],
            customCategories: [
                BlockCategory(id: "custom-piano", name: "Piano", group: music, symbol: "pianokeys", keywords: ["keys"]),
            ],
            customGroups: [music], removedCategories: ["doomscroll"],
            templates: [
                Template(
                    id: "lunch", categoryID: "lunch", startMinute: 750, length: 6, weekdays: Template.weekdaysOnly,
                    notifies: true),
                Template(id: "breakfast", categoryID: "breakfast", anchor: .wake, offset: 30, length: 4, weekdays: [1]),
                Template(id: "reading", categoryID: "reading", anchor: .bed, offset: 45, length: 6, isEnabled: false),
                Template(
                    id: "shower", categoryID: "shower", anchor: .after, afterCategoryID: "gym", offset: 15, length: 3),
            ],
            sleepShift: {
                var shift = SleepShift(
                    from: Schedule(wakeMinute: 540, bedMinute: 60), startDay: "2026-10-24", stepMinutes: 15,
                    everyDays: 2, leads: .wake)
                shift.isByFinishDay = true
                return shift
            }(),
            grid: GridMarks(gapMinutes: 15, labelMinutes: 30, hourGaps: .divided, gapHours: 6, dayParts: 3),
            windDownMinutes: 45, notifiesWindDown: false, notifiesBedtime: true, bedtimeNoticeMinutes: 20)
        var people = CategoryGroup.people
        people.name = "Company"
        settings.save(people)
        var lunch = settings.categories.first { $0.id == "lunch" }!
        lunch.name = "Midday meal"
        lunch.group = settings.groups.first { $0.id == "people" }
        settings.save(lunch)
        return settings
    }()

    static let timers = [
        LiveTimer(
            id: id(10), categoryID: "writing", countdown: 25 * 60,
            startedAt: Date(timeIntervalSinceReferenceDate: 783_110_000.5)),
        LiveTimer(id: id(11), categoryID: "coding", startedAt: Date(timeIntervalSinceReferenceDate: 783_111_000)),
    ]
}
