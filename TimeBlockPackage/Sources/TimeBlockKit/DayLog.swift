import Foundation

/// One day's logs in every track, as saved on disk.
public struct DayLog: Codable, Hashable, Sendable {
    /// See `Schedule.dayID`.
    public let day: String
    /// The wake time block indexes count from. Logs are moved when the schedule's wake time changes,
    /// so a block keeps its clock time.
    public private(set) var wakeMinute: Int
    /// The day's own schedule, as it was when its logs last changed, so a past day keeps its length when the
    /// schedule changes later. Nil for days saved before schedules were kept with them.
    public private(set) var schedule: Schedule?
    public private(set) var logs: [BlockLog]
    /// Whether the day's templates have been laid out on it (see `plan`).
    public private(set) var isPlanned: Bool

    public init(day: String, wakeMinute: Int, schedule: Schedule? = nil, logs: [BlockLog] = [], isPlanned: Bool = false) {
        self.day = day
        self.wakeMinute = wakeMinute
        self.schedule = schedule
        self.logs = logs
        self.isPlanned = isPlanned
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(String.self, forKey: .day)
        wakeMinute = try container.decode(Int.self, forKey: .wakeMinute)
        schedule = try container.decodeIfPresent(Schedule.self, forKey: .schedule)
        logs = try container.decode([BlockLog].self, forKey: .logs)
        // Days saved before templates were never planned.
        isPlanned = try container.decodeIfPresent(Bool.self, forKey: .isPlanned) ?? false
    }

    /// The day of the week, as a `Calendar` weekday (1 is Sunday).
    public func weekday(calendar: Calendar = .current) -> Int? {
        DayID.date(day, calendar: calendar).map { calendar.component(.weekday, from: $0) }
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

    /// Moves the ends of the run of one category at `range` in `track` to `newRange`: blocks it takes in are logged
    /// as it, overwriting what they held there, and blocks it lets go are cleared. The run keeps its note when it
    /// has one. Nothing changes unless `range` is all logged as one category.
    public mutating func resize(
        _ range: Range<Int>, to newRange: Range<Int>, in track: Track, schedule: Schedule,
        categories: [BlockCategory] = BlockCategory.defaults
    ) {
        guard !range.isEmpty, !newRange.isEmpty, newRange != range else { return }
        rebase(to: schedule)
        let (kept, cut) = split(range, in: track, categories: categories)
        let notes = Set(cut.map(\.note))
        guard let categoryID = cut.first?.categoryID, cut.allSatisfy({ $0.categoryID == categoryID }),
              cut.reduce(0, { $0 + $1.range.clamped(to: range).count }) == range.count
        else { return }
        logs = kept
        let (rest, _) = split(newRange, in: track, categories: categories)
        let note = notes.count == 1 ? notes.first ?? nil : nil
        logs = Self.joined(rest + [BlockLog(
            startIndex: newRange.lowerBound, length: newRange.count, categoryID: categoryID, note: note)])
    }

    /// Moves what `range` holds in `track` `offset` blocks along, gaps and notes included, so the blocks it lands on
    /// end up just like `range` was and the blocks it leaves are cleared. Nothing changes when `range` holds nothing.
    public mutating func move(
        _ range: Range<Int>, by offset: Int, in track: Track, schedule: Schedule,
        categories: [BlockCategory] = BlockCategory.defaults
    ) {
        guard !range.isEmpty, offset != 0 else { return }
        rebase(to: schedule)
        let (kept, cut) = split(range, in: track, categories: categories)
        guard !cut.isEmpty else { return }
        logs = kept
        let (rest, _) = split(range.lowerBound + offset..<range.upperBound + offset, in: track, categories: categories)
        let moved = cut.map { log in
            let inside = log.range.clamped(to: range)
            return BlockLog(
                startIndex: inside.lowerBound + offset, length: inside.count, categoryID: log.categoryID, note: log.note)
        }
        logs = Self.joined(rest + moved)
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

    /// Counts block indexes from `schedule`'s wake time from now on, and keeps it as the day's schedule.
    public mutating func rebase(to schedule: Schedule) {
        logs = logs(for: schedule)
        wakeMinute = schedule.wakeMinute
        self.schedule = schedule
    }

    /// The block after the last one logged in any track, or 0 when nothing is.
    public func loggedEnd(for schedule: Schedule) -> Int {
        logs(for: schedule).map(\.range.upperBound).max() ?? 0
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
        let own = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            .map { days(in: $0) }
        let candidates = [
            AppGroup.identifier.flatMap { fileManager.containerURL(forSecurityApplicationGroupIdentifier: $0) }
                .map { days(in: $0.appending(path: "Library/Application Support")) },
            own,
        ]
        for directory in candidates.compactMap({ $0 }) {
            if (try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)) != nil {
                if let own, directory != own { copyMissingDays(from: own, to: directory) }
                return LogStore(directory: directory)
            }
        }
        return LogStore(directory: fileManager.temporaryDirectory)
    }()

    private static func days(in base: URL) -> URL {
        base.appending(path: "TimeBlock/Days", directoryHint: .isDirectory)
    }

    /// Brings over the days an unsigned build saved in the app's own container, leaving those files as they were.
    private static func copyMissingDays(from source: URL, to directory: URL) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            try? fileManager.copyItem(at: file, to: directory.appending(path: file.lastPathComponent))
        }
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
