import Foundation

/// User settings shared between the app and its widget through the App Group.
public struct AppSettings: Codable, Hashable, Sendable {
    public var schedule: Schedule
    /// The view shown in the app window and menu bar. Each widget picks its own.
    public var track: Track

    public init(schedule: Schedule, track: Track = .activity) {
        self.schedule = schedule
        self.track = track
    }

    public static let standard = AppSettings(schedule: .standard)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schedule = try container.decode(Schedule.self, forKey: .schedule)
        // Settings saved before views existed have no track.
        track = try container.decodeIfPresent(Track.self, forKey: .track) ?? .activity
    }

    /// The day at `date`, drawn from `log` (which should be that day's, see `Schedule.dayID`).
    public func snapshot(at date: Date, log: DayLog, track: Track? = nil, calendar: Calendar = .current) -> DaySnapshot {
        DaySnapshot(
            status: DayStatus(schedule: schedule, nowMinute: schedule.timelineMinute(for: date, calendar: calendar)),
            logs: log.logs(for: schedule), categories: BlockCategory.defaults, track: track ?? self.track)
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
