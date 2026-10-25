import Foundation

/// User settings shared between the app and its widget through the App Group.
public struct AppSettings: Codable, Hashable, Sendable {
    /// The schedule you keep, or are heading to while `sleepShift` gets you there. A day's own is `schedule(on:)`.
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
    /// Ids of activities (and postures) the user removed. They're kept, retired, so blocks logged with them keep
    /// their name and color, and can be put back.
    public var removedCategories: [String]
    /// Time pre-logged on the days it comes back on, such as meals and coffee.
    public var templates: [Template]
    /// Moves you to `schedule` a step at a time.
    public var sleepShift: SleepShift?
    /// How the grid marks the time.
    public var grid: GridMarks

    public init(
        schedule: Schedule, track: Track = .activity, favorites: [String] = BlockCategory.defaultFavorites,
        customCategories: [BlockCategory] = [], customGroups: [CategoryGroup] = [],
        editedCategories: [BlockCategory] = [], editedGroups: [CategoryGroup] = [], removedCategories: [String] = [],
        templates: [Template] = [], sleepShift: SleepShift? = nil, grid: GridMarks = .standard
    ) {
        self.schedule = schedule
        self.track = track
        self.favorites = favorites
        self.customCategories = customCategories
        self.customGroups = customGroups
        self.editedCategories = editedCategories
        self.editedGroups = editedGroups
        self.removedCategories = removedCategories
        self.templates = templates
        self.sleepShift = sleepShift
        self.grid = grid
    }

    /// The schedule on `day`: `schedule`, or the step a sleep shift has got to.
    public func schedule(on day: String, calendar: Calendar = .current) -> Schedule {
        sleepShift?.schedule(on: day, target: schedule, calendar: calendar) ?? schedule
    }

    /// The day a moment belongs to (see `Schedule.dayID`), going by the rollover of the date it falls on.
    public func dayID(for date: Date, calendar: Calendar = .current) -> String {
        schedule(on: DayID.string(from: date, calendar: calendar), calendar: calendar).dayID(for: date, calendar: calendar)
    }

    /// Ends a sleep shift that has got you to `schedule` by `day`. Returns whether it did.
    @discardableResult
    public mutating func endSleepShiftIfDone(on day: String, calendar: Calendar = .current) -> Bool {
        guard let shift = sleepShift, shift.isDone(on: day, target: schedule, calendar: calendar) else { return false }
        sleepShift = nil
        return true
    }

    /// The schedule of the day `date` belongs to.
    public func schedule(for date: Date, calendar: Calendar = .current) -> Schedule {
        schedule(on: dayID(for: date, calendar: calendar), calendar: calendar)
    }

    /// Every activity group as it is now, in order: the built-in ones, then your own.
    public var groups: [CategoryGroup] {
        CategoryGroup.builtIn.map { group in editedGroups.first { $0.id == group.id } ?? group } + customGroups
    }

    /// Everything a block can be logged as, in every track, with your edits: activities group by group (your own
    /// after the built-in ones in each), then postures, then retired activities. The ones you removed stay in
    /// place, retired.
    public var categories: [BlockCategory] {
        let groups = groups
        let edits = Dictionary(editedCategories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let removed = Set(removedCategories)
        let resolve = { (category: BlockCategory) in
            var category = Self.resolved(edits[category.id] ?? category, in: groups)
            category.isRemoved = removed.contains(category.id)
            return category
        }
        let byGroup = Dictionary(grouping: (BlockCategory.activities + customCategories).map(resolve)) {
            $0.group?.id ?? ""
        }
        return groups.flatMap { byGroup[$0.id] ?? [] } + BlockCategory.body.map(resolve)
            + customCategories.filter { $0.track != .activity }.map(resolve) + BlockCategory.retired.map(resolve)
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

    /// Takes an activity (or posture) out of the palette, search and library. Blocks logged with it keep it, and
    /// it keeps its star for when it's put back.
    public mutating func remove(_ id: String) {
        if !removedCategories.contains(id) { removedCategories.append(id) }
    }

    /// Puts a removed activity back as it was.
    public mutating func restore(_ id: String) {
        removedCategories.removeAll { $0 == id }
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
        removedCategories = try container.decodeIfPresent([String].self, forKey: .removedCategories) ?? []
        templates = try container.decodeIfPresent([Template].self, forKey: .templates) ?? []
        sleepShift = try container.decodeIfPresent(SleepShift.self, forKey: .sleepShift)
        grid = try container.decodeIfPresent(GridMarks.self, forKey: .grid) ?? .standard
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
        case schedule, track, favorites, customCategories, customGroups, editedCategories, editedGroups,
             removedCategories, templates, sleepShift, grid
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
        try container.encode(removedCategories, forKey: .removedCategories)
        try container.encode(templates, forKey: .templates)
        try container.encodeIfPresent(sleepShift, forKey: .sleepShift)
        try container.encode(grid, forKey: .grid)
    }

    /// The day at `date`, drawn from `log` (which should be that day's, see `Schedule.dayID`).
    public func snapshot(at date: Date, log: DayLog, track: Track? = nil, calendar: Calendar = .current) -> DaySnapshot {
        let schedule = schedule(for: date, calendar: calendar)
        return DaySnapshot(
            status: DayStatus(schedule: schedule, nowMinute: schedule.timelineMinute(for: date, calendar: calendar)),
            logs: log.logs(for: schedule), categories: categories, favorites: favorites,
            track: track ?? self.track, grid: grid)
    }
}

/// How the grid marks the time, so a block's time can be read off its place: with wider gaps along each hour row.
public struct GridMarks: Codable, Hashable, Sendable {
    /// Minutes between the wider gaps that split each row, 10, 15, 20 or 30, or 0 for none.
    public var gapMinutes: Int

    public init(gapMinutes: Int = 30) {
        self.gapMinutes = gapMinutes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = Self.standard
        gapMinutes = try container.decodeIfPresent(Int.self, forKey: .gapMinutes) ?? standard.gapMinutes
    }

    public static let standard = GridMarks()

    /// Blocks between the wider gaps, or nil when there are none.
    public var blocksPerGroup: Int? {
        gapMinutes > 0 ? gapMinutes / Schedule.blockMinutes : nil
    }
}

public enum SettingsStore {
    private static let key = "settings"

    /// In the App Group when the build has one; otherwise in the process's own container, so an unsigned app still
    /// works and its widget shows the standard schedule.
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier ?? AppGroup.unsignedSuite) ?? .standard
    }

    public static func load() -> AppSettings {
        var data = defaults.data(forKey: key)
        // The first signed run takes over what the app saved unsigned.
        if data == nil, AppGroup.identifier != nil,
           let unsigned = UserDefaults(suiteName: AppGroup.unsignedSuite)?.data(forKey: key) {
            defaults.set(unsigned, forKey: key)
            data = unsigned
        }
        guard let data, let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
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
