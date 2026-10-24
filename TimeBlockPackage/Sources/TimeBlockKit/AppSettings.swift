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
    /// Groups the user added after the built-in ones.
    public var customGroups: [CategoryGroup]
    /// Built-in activities and postures as the user edited them, replacing the originals.
    public var editedCategories: [BlockCategory]
    /// Built-in groups as the user renamed or recolored them, replacing the originals.
    public var editedGroups: [CategoryGroup]

    public init(
        schedule: Schedule, track: Track = .activity, favorites: [String] = BlockCategory.defaultFavorites,
        customCategories: [BlockCategory] = [], customGroups: [CategoryGroup] = [],
        editedCategories: [BlockCategory] = [], editedGroups: [CategoryGroup] = []
    ) {
        self.schedule = schedule
        self.track = track
        self.favorites = favorites
        self.customCategories = customCategories
        self.customGroups = customGroups
        self.editedCategories = editedCategories
        self.editedGroups = editedGroups
    }

    /// Every activity group as it is now, in order: the built-in ones, then your own.
    public var groups: [CategoryGroup] {
        CategoryGroup.builtIn.map { group in editedGroups.first { $0.id == group.id } ?? group } + customGroups
    }

    /// Everything a block can be logged as, in every track, with your edits: activities group by group (your own
    /// after the built-in ones in each), then postures, then retired activities.
    public var categories: [BlockCategory] {
        let groups = groups
        let edits = Dictionary(editedCategories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let resolve = { (category: BlockCategory) in Self.resolved(edits[category.id] ?? category, in: groups) }
        let byGroup = Dictionary(grouping: (BlockCategory.activities + customCategories).map(resolve)) {
            $0.group?.id ?? ""
        }
        return groups.flatMap { byGroup[$0.id] ?? [] } + BlockCategory.body.map(resolve)
            + customCategories.filter { $0.track != .activity } + BlockCategory.retired.map(resolve)
    }

    /// An activity with its group as it is now (renamed or recolored), or in Life when its group is gone.
    private static func resolved(_ category: BlockCategory, in groups: [CategoryGroup]) -> BlockCategory {
        guard category.track == .activity else { return category }
        var category = category
        let id = category.group?.id ?? ""
        category.group = groups.first { $0.id == id } ?? groups.first { $0.id == CategoryGroup.life.id }
        return category
    }

    /// Whether `id` is a built-in activity or group the user changed.
    public func isEdited(_ id: String) -> Bool {
        editedCategories.contains { $0.id == id } || editedGroups.contains { $0.id == id }
    }

    /// Saves an edited activity: your own in place, a built-in one as an edit over the original (or none, when
    /// it's the same as the original).
    public mutating func save(_ category: BlockCategory) {
        if let index = customCategories.firstIndex(where: { $0.id == category.id }) {
            customCategories[index] = category
        } else if let original = BlockCategory.defaults.first(where: { $0.id == category.id }),
                  Self.resolved(original, in: groups) == category {
            reset(category.id)
        } else if let index = editedCategories.firstIndex(where: { $0.id == category.id }) {
            editedCategories[index] = category
        } else {
            editedCategories.append(category)
        }
    }

    /// Saves an edited group: your own in place, a built-in one as an edit over the original (or none, when it's
    /// the same as the original).
    public mutating func save(_ group: CategoryGroup) {
        if let index = customGroups.firstIndex(where: { $0.id == group.id }) {
            customGroups[index] = group
        } else if CategoryGroup.builtIn.contains(group) {
            reset(group.id)
        } else if let index = editedGroups.firstIndex(where: { $0.id == group.id }) {
            editedGroups[index] = group
        } else {
            editedGroups.append(group)
        }
    }

    /// Puts a built-in activity or group back the way it came.
    public mutating func reset(_ id: String) {
        editedCategories.removeAll { $0.id == id }
        editedGroups.removeAll { $0.id == id }
    }

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
        customGroups = try container.decodeIfPresent([CategoryGroup].self, forKey: .customGroups) ?? []
        editedCategories = try container.decodeIfPresent([BlockCategory].self, forKey: .editedCategories) ?? []
        editedGroups = try container.decodeIfPresent([CategoryGroup].self, forKey: .editedGroups) ?? []
        // Activities save only their group's id; put the groups themselves back. Edits that match the original
        // aren't edits.
        editedGroups.removeAll { CategoryGroup.builtIn.contains($0) }
        let groups = groups
        customCategories = customCategories.map { Self.resolved($0, in: groups) }
        editedCategories = editedCategories.map { Self.resolved($0, in: groups) }.filter { edited in
            BlockCategory.defaults.first { $0.id == edited.id }.map { Self.resolved($0, in: groups) } != edited
        }
        if let legacy, container.contains(.favorites) == false {
            favorites += legacy.map(\.id).filter { $0.hasPrefix("custom-") }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schedule, track, favorites, customCategories, customGroups, editedCategories, editedGroups
        case legacyCategories = "categories"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schedule, forKey: .schedule)
        try container.encode(track, forKey: .track)
        try container.encode(favorites, forKey: .favorites)
        try container.encode(customCategories, forKey: .customCategories)
        try container.encode(customGroups, forKey: .customGroups)
        try container.encode(editedCategories, forKey: .editedCategories)
        try container.encode(editedGroups, forKey: .editedGroups)
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
