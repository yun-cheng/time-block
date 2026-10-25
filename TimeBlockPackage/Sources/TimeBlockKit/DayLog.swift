import Foundation
import Security

/// One day's logs in every track, as saved on disk.
public struct DayLog: Codable, Hashable, Sendable {
    /// See `Schedule.dayID`.
    public let day: String
    /// The wake time block indexes count from. Logs are moved when the schedule's wake time changes,
    /// so a block keeps its clock time.
    public private(set) var wakeMinute: Int
    public private(set) var logs: [BlockLog]
    /// Whether the day's templates have been laid out on it (see `plan`).
    public private(set) var isPlanned: Bool

    public init(day: String, wakeMinute: Int, logs: [BlockLog] = [], isPlanned: Bool = false) {
        self.day = day
        self.wakeMinute = wakeMinute
        self.logs = logs
        self.isPlanned = isPlanned
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(String.self, forKey: .day)
        wakeMinute = try container.decode(Int.self, forKey: .wakeMinute)
        logs = try container.decode([BlockLog].self, forKey: .logs)
        // Days saved before templates were never planned.
        isPlanned = try container.decodeIfPresent(Bool.self, forKey: .isPlanned) ?? false
    }

    /// The day of the week, as a `Calendar` weekday (1 is Sunday).
    public func weekday(calendar: Calendar = .current) -> Int? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return nil }
        return calendar.component(.weekday, from: date)
    }

    /// The logs with block indexes counted from `schedule`'s wake time.
    public func logs(for schedule: Schedule) -> [BlockLog] {
        let shift = (wakeMinute - schedule.wakeMinute) / Schedule.blockMinutes
        guard shift != 0 else { return logs }
        return logs.map { log in
            var log = log
            log.startIndex += shift
            return log
        }
    }

    /// Gives `range` to a category, or clears it with nil. Only logs in the category's track (or `track`,
    /// when clearing) change: parts outside `range` are kept, and runs of one category join up. A run that
    /// is given another category as a whole keeps its note.
    public mutating func set(
        _ range: Range<Int>, to categoryID: String?, in track: Track, schedule: Schedule,
        categories: [BlockCategory] = BlockCategory.defaults
    ) {
        guard !range.isEmpty else { return }
        rebase(to: schedule)
        let (kept, cut) = split(range, in: track, categories: categories)
        var logs = kept
        if let categoryID {
            let notes = Set(cut.map(\.note))
            let note = cut.allSatisfy({ range.contains($0.range) }) && notes.count == 1 ? notes.first ?? nil : nil
            logs.append(BlockLog(startIndex: range.lowerBound, length: range.count, categoryID: categoryID, note: note))
        }
        self.logs = Self.joined(logs)
    }

    /// Writes `note` on the logged blocks of `range` in `track`, or takes their note off with nil or blank.
    /// Logs reaching past `range` are split, so the note covers exactly those blocks.
    public mutating func setNote(
        _ note: String?, for range: Range<Int>, in track: Track, schedule: Schedule,
        categories: [BlockCategory] = BlockCategory.defaults
    ) {
        guard !range.isEmpty else { return }
        rebase(to: schedule)
        let note = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let (kept, cut) = split(range, in: track, categories: categories)
        let noted = cut.map { log in
            let inside = log.range.clamped(to: range)
            return BlockLog(
                startIndex: inside.lowerBound, length: inside.count, categoryID: log.categoryID,
                note: note?.isEmpty == false ? note : nil, source: log.source)
        }
        logs = Self.joined(kept + noted)
    }

    /// Pre-logs the templates that come back on this day, from block `index` on, in the blocks still free in their
    /// category's track. What templates logged from `index` on before is taken back first, so a changed template
    /// moves; blocks before `index` keep what they had. Paused templates, and ones for retired activities, log
    /// nothing.
    public mutating func plan(
        _ templates: [Template], from index: Int = 0, schedule: Schedule,
        categories: [BlockCategory] = BlockCategory.defaults, calendar: Calendar = .current
    ) {
        rebase(to: schedule)
        logs = logs.compactMap { log in
            guard log.source == .template, log.range.upperBound > index else { return log }
            guard log.startIndex < index else { return nil }
            var kept = log
            kept.length = index - log.startIndex
            return kept
        }
        let byID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let weekday = weekday(calendar: calendar)
        for template in templates where template.isEnabled && weekday.map(template.weekdays.contains) == true {
            guard let category = byID[template.categoryID], !category.isRetired else { continue }
            let taken = Set(logs.filter { byID[$0.categoryID]?.track == category.track }.flatMap(\.range))
            let range = template.range(in: schedule)
            var start: Int?
            for block in max(index, range.lowerBound)..<max(index, range.upperBound) + 1 {
                let isFree = block < range.upperBound && !taken.contains(block)
                if isFree, start == nil { start = block }
                if !isFree, let from = start {
                    logs.append(BlockLog(
                        startIndex: from, length: block - from, categoryID: category.id, source: .template))
                    start = nil
                }
            }
        }
        logs = Self.joined(logs)
        isPlanned = true
    }

    /// Counts block indexes from `schedule`'s wake time from now on.
    private mutating func rebase(to schedule: Schedule) {
        logs = logs(for: schedule)
        wakeMinute = schedule.wakeMinute
    }

    /// The logs with `track`'s blocks in `range` taken out, and the logs in `track` that overlapped it.
    private func split(_ range: Range<Int>, in track: Track, categories: [BlockCategory]) -> (kept: [BlockLog], cut: [BlockLog]) {
        let trackOf = Dictionary(categories.map { ($0.id, $0.track) }, uniquingKeysWith: { first, _ in first })
        var kept: [BlockLog] = []
        var cut: [BlockLog] = []
        for log in logs {
            guard trackOf[log.categoryID] == track, log.range.overlaps(range) else {
                kept.append(log)
                continue
            }
            cut.append(log)
            if log.startIndex < range.lowerBound {
                var left = log
                left.length = range.lowerBound - log.startIndex
                kept.append(left)
            }
            if log.range.upperBound > range.upperBound {
                kept.append(BlockLog(
                    startIndex: range.upperBound, length: log.range.upperBound - range.upperBound,
                    categoryID: log.categoryID, note: log.note, source: log.source))
            }
        }
        return (kept, cut)
    }

    /// Sorted, with touching logs of the same category, source and note made one.
    private static func joined(_ logs: [BlockLog]) -> [BlockLog] {
        var joined: [BlockLog] = []
        for log in logs.sorted(by: { $0.startIndex < $1.startIndex }) {
            if let i = joined.lastIndex(where: {
                $0.range.upperBound == log.startIndex && $0.categoryID == log.categoryID
                    && $0.source == log.source && $0.note == log.note
            }) {
                joined[i].length += log.length
            } else {
                joined.append(log)
            }
        }
        return joined
    }
}

/// Saves each day's logs as a JSON file.
public struct LogStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// In the App Group container when the build has one, so the widget can read it; otherwise in the
    /// app's own Application Support, where only the app sees it.
    public static let shared: LogStore = {
        let fileManager = FileManager.default
        let candidates = [
            hasAppGroup
                ? fileManager.containerURL(forSecurityApplicationGroupIdentifier: SettingsStore.appGroup)?
                    .appending(path: "Library/Application Support")
                : nil,
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
        ]
        for base in candidates.compactMap({ $0 }) {
            let directory = base.appending(path: "TimeBlock/Days", directoryHint: .isDirectory)
            if (try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)) != nil {
                return LogStore(directory: directory)
            }
        }
        return LogStore(directory: fileManager.temporaryDirectory)
    }()

    /// Whether this build is signed with the App Group. Without it, touching the group container makes
    /// macOS ask the user for access to "other apps' data".
    private static var hasAppGroup: Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let groups = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil)
        else { return false }
        return (groups as? [String])?.contains(SettingsStore.appGroup) ?? false
        #else
        return true
        #endif
    }

    /// The saved logs for `day`, or an empty day.
    public func load(day: String, wakeMinute: Int) -> DayLog {
        guard let data = try? Data(contentsOf: url(for: day)),
              let log = try? JSONDecoder().decode(DayLog.self, from: data)
        else { return DayLog(day: day, wakeMinute: wakeMinute) }
        return log
    }

    public func save(_ log: DayLog) throws {
        try JSONEncoder().encode(log).write(to: url(for: log.day), options: .atomic)
    }

    private func url(for day: String) -> URL {
        directory.appending(path: "\(day).json")
    }
}
