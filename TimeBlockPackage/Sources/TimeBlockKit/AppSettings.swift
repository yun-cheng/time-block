import Foundation

/// User settings shared between the app and its widget through the App Group.
public struct AppSettings: Codable, Hashable, Sendable {
    public var schedule: Schedule
    /// The view shown in the app window and menu bar. Each widget picks its own.
    public var track: Track
    /// Starred activities (and postures). The palette shows these, by group; search finds the rest.
    public var favorites: [String]
    /// Activities the user added to the built-in ones.
    public var customCategories: [BlockCategory]

    public init(
        schedule: Schedule, track: Track = .activity, favorites: [String] = BlockCategory.defaultFavorites,
        customCategories: [BlockCategory] = []
    ) {
        self.schedule = schedule
        self.track = track
        self.favorites = favorites
        self.customCategories = customCategories
    }

    /// Everything a block can be logged as, in every track.
    public var categories: [BlockCategory] { BlockCategory.defaults + customCategories }

    public static let standard = AppSettings(schedule: .standard)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schedule = try container.decode(Schedule.self, forKey: .schedule)
        // Settings saved before views existed have no track.
        track = try container.decodeIfPresent(Track.self, forKey: .track) ?? .activity
        favorites = try container.decodeIfPresent([String].self, forKey: .favorites) ?? BlockCategory.defaultFavorites
        // Before favorites, settings kept every category; the user's own carry over.
        let legacy = (try? container.decodeIfPresent([BlockCategory].self, forKey: .legacyCategories)) ?? nil
        customCategories = (try? container.decodeIfPresent([BlockCategory].self, forKey: .customCategories))
            ?? legacy?.filter { $0.id.hasPrefix("custom-") } ?? []
        if let legacy, container.contains(.favorites) == false {
            favorites += legacy.map(\.id).filter { $0.hasPrefix("custom-") }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schedule, track, favorites, customCategories
        case legacyCategories = "categories"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schedule, forKey: .schedule)
        try container.encode(track, forKey: .track)
        try container.encode(favorites, forKey: .favorites)
        try container.encode(customCategories, forKey: .customCategories)
    }

    /// The day at `date`, drawn from `log` (which should be that day's, see `Schedule.dayID`).
    public func snapshot(at date: Date, log: DayLog, track: Track? = nil, calendar: Calendar = .current) -> DaySnapshot {
        DaySnapshot(
            status: DayStatus(schedule: schedule, nowMinute: schedule.timelineMinute(for: date, calendar: calendar)),
            logs: log.logs(for: schedule), categories: categories, favorites: favorites,
            track: track ?? self.track)
    }
}

public enum SettingsStore {
    public static let appGroup = "group.dev.timeblock"
    private static let key = "settings"

    /// Falls back to the process's own defaults when the App Group container isn't available
    /// (e.g. an unsigned build), so the app still works; the widget then shows the standard schedule.
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    public static func load() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return .standard }
        return settings
    }

    public static func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

public enum BlockClock {
    /// The start of the block containing `date`, followed by the next `count` block starts.
    public static func boundaries(from date: Date, count: Int, calendar: Calendar = .current) -> [Date] {
        let seconds = Double(Schedule.blockMinutes * 60)
        let minuteStart = calendar.dateInterval(of: .minute, for: date)?.start ?? date
        let minute = calendar.component(.minute, from: minuteStart)
        let blockStart = minuteStart.addingTimeInterval(-Double(minute % Schedule.blockMinutes) * 60)
        return (0...count).map { blockStart.addingTimeInterval(Double($0) * seconds) }
    }
}
