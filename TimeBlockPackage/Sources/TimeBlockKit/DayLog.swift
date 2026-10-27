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
    /// The stretches timers ran, to the second, in the order they ended (see `record`).
    public private(set) var sessions: [TimerSession]

    public init(
        day: String, wakeMinute: Int, schedule: Schedule? = nil, logs: [BlockLog] = [], isPlanned: Bool = false,
        sessions: [TimerSession] = []
    ) {
        self.day = day
        self.wakeMinute = wakeMinute
        self.schedule = schedule
        self.logs = logs
        self.isPlanned = isPlanned
        self.sessions = sessions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(String.self, forKey: .day)
        wakeMinute = try container.decode(Int.self, forKey: .wakeMinute)
        schedule = try container.decodeIfPresent(Schedule.self, forKey: .schedule)
        logs = try container.decode([BlockLog].self, forKey: .logs)
        // Days saved before templates were never planned.
        isPlanned = try container.decodeIfPresent(Bool.self, forKey: .isPlanned) ?? false
        sessions = try container.decodeIfPresent([TimerSession].self, forKey: .sessions) ?? []
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

    /// Gives `range` to a category alone, in place of everything it held, or clears it with nil. Only logs in the
    /// category's track (or `track`, when clearing) change: parts outside `range` are kept, and runs of one category
    /// join up. A run that is given another category as a whole keeps its note. With `layer`, only that activity is
    /// replaced or cleared, and the one replacing it joins the rest.
    public mutating func set(
        _ range: Range<Int>, to categoryID: String?, in track: Track, schedule: Schedule,
        categories: [BlockCategory] = BlockCategory.defaults, layer: String? = nil
    ) {
        guard !range.isEmpty else { return }
        rebase(to: schedule)
        let (kept, cut) = split(range, in: track, categories: categories) {
            layer == nil || $0.categoryID == layer || $0.categoryID == categoryID
        }
        var logs = kept
        if let categoryID {
            let replaced = layer.map { layer in cut.filter { $0.categoryID == layer } } ?? cut
            let notes = Set(replaced.map(\.note))
            let note = replaced.allSatisfy({ range.contains($0.range) }) && notes.count == 1 ? notes.first ?? nil : nil
            logs.append(BlockLog(startIndex: range.lowerBound, length: range.count, categoryID: categoryID, note: note))
        }
        self.logs = Self.joined(logs)
    }

    /// Whether every block of `range` holds `categoryID`, alone or with others.
    public func holds(_ categoryID: String, throughout range: Range<Int>, schedule: Schedule) -> Bool {
        let held = Set(logs(for: schedule).filter { $0.categoryID == categoryID }.flatMap(\.range))
        return !range.isEmpty && range.allSatisfy(held.contains)
    }

    /// Takes `categoryID` off `range` when every block of it holds it; otherwise adds it to what the blocks
    /// hold, as one more activity at the same time. Nothing else they hold changes.
    public mutating func toggle(
        _ categoryID: String, in range: Range<Int>, schedule: Schedule,
        categories: [BlockCategory] = BlockCategory.defaults
    ) {
        guard !range.isEmpty, let track = categories.first(where: { $0.id == categoryID })?.track else { return }
        let isHeld = holds(categoryID, throughout: range, schedule: schedule)
        rebase(to: schedule)
        var (logs, _) = split(range, in: track, categories: categories) { $0.categoryID == categoryID }
        if !isHeld {
            logs.append(BlockLog(startIndex: range.lowerBound, length: range.count, categoryID: categoryID))
        }
        self.logs = Self.joined(logs)
    }

    /// Adds `categoryID` to the blocks of `range` that don't hold it yet, alongside what they hold. Blocks holding it
    /// already keep it as it was, note and all.
    public mutating func add(_ categoryID: String, in range: Range<Int>, schedule: Schedule) {
        guard !range.isEmpty else { return }
        rebase(to: schedule)
        let held = Set(logs.filter { $0.categoryID == categoryID }.flatMap(\.range))
        let added = Self.runs(in: range) { !held.contains($0) }.map {
            BlockLog(startIndex: $0.lowerBound, length: $0.count, categoryID: categoryID)
        }
        logs = Self.joined(logs + added)
    }

    /// Logs a stretch a timer ran: its activity is added to every block of the day it ran in, any part of it, and its
    /// exact times are kept, to show over those blocks.
    public mutating func record(_ session: TimerSession, schedule: Schedule, calendar: Calendar = .current) {
        let range = session.blocks(on: day, schedule: schedule, calendar: calendar)
        guard !range.isEmpty else { return }
        add(session.categoryID, in: range, schedule: schedule)
        sessions.append(session)
    }

    /// Writes `note` on the logged blocks of `range` in `track`, or takes their note off with nil or blank.
    /// Logs reaching past `range` are split, so the note covers exactly those blocks. With `layer`, only that activity
    /// takes it.
    public mutating func setNote(
        _ note: String?, for range: Range<Int>, in track: Track, schedule: Schedule,
        categories: [BlockCategory] = BlockCategory.defaults, layer: String? = nil
    ) {
        guard !range.isEmpty else { return }
        rebase(to: schedule)
        let note = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let (kept, cut) = split(range, in: track, categories: categories) { layer == nil || $0.categoryID == layer }
        let noted = cut.map { log in
            let inside = log.range.clamped(to: range)
            return BlockLog(
                startIndex: inside.lowerBound, length: inside.count, categoryID: log.categoryID,
                note: note?.isEmpty == false ? note : nil, source: log.source, templateID: log.templateID)
        }
        logs = Self.joined(kept + noted)
    }

    /// Moves the ends of the run of one category at `range` in `track` to `newRange`: blocks it takes in are logged
    /// as it, overwriting what they held there, and blocks it lets go are cleared. The run keeps its note when it
    /// has one. Nothing changes unless `range` is all logged as one category. With `layer`, only that activity's run
    /// moves its ends, alongside what the blocks it takes in hold.
    public mutating func resize(
        _ range: Range<Int>, to newRange: Range<Int>, in track: Track, schedule: Schedule,
        categories: [BlockCategory] = BlockCategory.defaults, layer: String? = nil
    ) {
        guard !range.isEmpty, !newRange.isEmpty, newRange != range else { return }
        rebase(to: schedule)
        let (kept, cut) = split(range, in: track, categories: categories) { layer == nil || $0.categoryID == layer }
        let notes = Set(cut.map(\.note))
        guard let categoryID = cut.first?.categoryID, cut.allSatisfy({ $0.categoryID == categoryID }),
              cut.reduce(0, { $0 + $1.range.clamped(to: range).count }) == range.count
        else { return }
        logs = kept
        let (rest, _) = split(newRange, in: track, categories: categories) { layer == nil || $0.categoryID == categoryID }
        let note = notes.count == 1 ? notes.first ?? nil : nil
        logs = Self.joined(rest + [BlockLog(
            startIndex: newRange.lowerBound, length: newRange.count, categoryID: categoryID, note: note)])
    }

    /// Moves what `range` holds in `track` `offset` blocks along, gaps and notes included, so the blocks it lands on
    /// end up just like `range` was and the blocks it leaves are cleared. Nothing changes when `range` holds nothing.
    /// With `layer`, only that activity moves, alongside what the blocks it lands on hold.
    public mutating func move(
        _ range: Range<Int>, by offset: Int, in track: Track, schedule: Schedule,
        categories: [BlockCategory] = BlockCategory.defaults, layer: String? = nil
    ) {
        guard !range.isEmpty, offset != 0 else { return }
        rebase(to: schedule)
        let isMoved = { (log: BlockLog) in layer == nil || log.categoryID == layer }
        let (kept, cut) = split(range, in: track, categories: categories, where: isMoved)
        guard !cut.isEmpty else { return }
        logs = kept
        let (rest, _) = split(
            range.lowerBound + offset..<range.upperBound + offset, in: track, categories: categories, where: isMoved)
        let moved = cut.map { log in
            let inside = log.range.clamped(to: range)
            return BlockLog(
                startIndex: inside.lowerBound + offset, length: inside.count, categoryID: log.categoryID, note: log.note)
        }
        logs = Self.joined(rest + moved)
    }

    /// Pre-logs the templates that come back on this day, from block `index` on, in the blocks still free in their
    /// category's track. What templates logged from `index` on before is taken back first, so a changed template
    /// moves; blocks before `index` keep what they had. One that starts after an activity is laid out after each
    /// time that day it's logged or pre-logged, and not at all when it isn't. Paused templates, and ones for retired
    /// activities, log nothing.
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
        let comingBack = templates.filter { comesBack($0, calendar: calendar) }
        for template in comingBack where template.anchor != .after {
            preLog(template, in: template.range(in: schedule), from: index, categories: categories)
        }
        for template in Template.inLayingOrder(comingBack) {
            for end in ends(of: template) {
                preLog(template, in: template.range(in: schedule, following: end), from: index, categories: categories)
            }
        }
        logs = Self.joined(logs)
        isPlanned = true
    }

    /// Moves the templates that start after an activity, from block `index` on, to follow it where it is now that
    /// the logs have changed from `before`: logged, moved or cleared. Each time of it that ends where it did keeps
    /// what follows it as it is, cleared blocks and all.
    public mutating func follow(
        _ templates: [Template], from index: Int, after before: DayLog, schedule: Schedule,
        categories: [BlockCategory] = BlockCategory.defaults, calendar: Calendar = .current
    ) {
        var before = before
        before.rebase(to: schedule)
        let following = Template.inLayingOrder(templates.filter { comesBack($0, calendar: calendar) })
        var changed = false
        for template in following {
            let ends = ends(of: template)
            let old = before.ends(of: template)
            guard ends != old else { continue }
            if let track = categories.first(where: { $0.id == template.categoryID })?.track {
                for end in old where !ends.contains(end) {
                    let range = template.range(in: schedule, following: end)
                    guard range.upperBound > index else { continue }
                    logs = split(max(index, range.lowerBound)..<range.upperBound, in: track, categories: categories) {
                        $0.templateID == template.id
                    }.kept
                }
            }
            for end in ends where !old.contains(end) {
                preLog(template, in: template.range(in: schedule, following: end), from: index, categories: categories)
            }
            changed = true
        }
        if changed { logs = Self.joined(logs) }
    }

    /// Where the activity `template` starts after ends each time it's on this day, logged or pre-logged by anything
    /// but it, in order; none when it isn't, or `template` doesn't start after one.
    public func ends(of template: Template) -> [Int] {
        guard template.anchor == .after, let id = template.afterCategoryID else { return [] }
        let ranges = logs.filter { $0.categoryID == id && $0.templateID != template.id }.map(\.range)
            .sorted { $0.lowerBound < $1.lowerBound }
        var ends: [Int] = []
        for range in ranges {
            // Touching or overlapping runs of it are one time.
            if let last = ends.last, range.lowerBound <= last {
                ends[ends.count - 1] = max(last, range.upperBound)
            } else {
                ends.append(range.upperBound)
            }
        }
        return ends
    }

    private func comesBack(_ template: Template, calendar: Calendar) -> Bool {
        template.isEnabled && weekday(calendar: calendar).map(template.weekdays.contains) == true
    }

    /// Pre-logs `template` in the blocks of `range` from `index` on that are still free in its category's track.
    private mutating func preLog(
        _ template: Template, in range: Range<Int>, from index: Int, categories: [BlockCategory]
    ) {
        guard let category = categories.first(where: { $0.id == template.categoryID }), !category.isRetired else {
            return
        }
        let trackOf = Dictionary(categories.map { ($0.id, $0.track) }, uniquingKeysWith: { first, _ in first })
        let taken = Set(logs.filter { trackOf[$0.categoryID] == category.track }.flatMap(\.range))
        logs += Self.runs(in: range.clamped(to: index..<max(index, range.upperBound))) { !taken.contains($0) }.map {
            BlockLog(
                startIndex: $0.lowerBound, length: $0.count, categoryID: category.id, source: .template,
                templateID: template.id)
        }
    }

    /// The unbroken runs of blocks in `range` that `isFree` picks, in order.
    private static func runs(in range: Range<Int>, where isFree: (Int) -> Bool) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var start: Int?
        for block in range.lowerBound...range.upperBound {
            if block < range.upperBound, isFree(block) {
                if start == nil { start = block }
            } else if let from = start {
                runs.append(from..<block)
                start = nil
            }
        }
        return runs
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

    /// The logs with `track`'s blocks in `range` taken out, and the logs in `track` that overlapped it. Only the logs
    /// `isCut` picks are taken out; the rest are kept whole.
    private func split(
        _ range: Range<Int>, in track: Track, categories: [BlockCategory], where isCut: (BlockLog) -> Bool = { _ in true }
    ) -> (kept: [BlockLog], cut: [BlockLog]) {
        let trackOf = Dictionary(categories.map { ($0.id, $0.track) }, uniquingKeysWith: { first, _ in first })
        var kept: [BlockLog] = []
        var cut: [BlockLog] = []
        for log in logs {
            guard trackOf[log.categoryID] == track, log.range.overlaps(range), isCut(log) else {
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
                    categoryID: log.categoryID, note: log.note, source: log.source, templateID: log.templateID))
            }
        }
        return (kept, cut)
    }

    /// Touching logs of the same category, source and note made one. Their order is kept, since logs that overlap are
    /// layered in it when all else is even (see `DayGrid.cells`): two that join take the later one's place, as the
    /// one logged last.
    private static func joined(_ logs: [BlockLog]) -> [BlockLog] {
        var joined: [BlockLog] = []
        for log in logs {
            var log = log
            while let i = joined.firstIndex(where: {
                ($0.range.upperBound == log.startIndex || log.range.upperBound == $0.startIndex)
                    && $0.categoryID == log.categoryID && $0.source == log.source && $0.note == log.note
                    && $0.templateID == log.templateID
            }) {
                let other = joined.remove(at: i)
                log = BlockLog(
                    id: other.startIndex < log.startIndex ? other.id : log.id,
                    startIndex: min(other.startIndex, log.startIndex), length: other.length + log.length,
                    categoryID: log.categoryID, note: log.note, source: log.source, templateID: log.templateID)
            }
            joined.append(log)
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

    /// The saved logs for `day`, or an empty day. A file that can't be read is moved aside first, out of the days
    /// (which are ".json"), so saving the empty day doesn't write over it.
    public func load(day: String, wakeMinute: Int) -> DayLog {
        let url = url(for: day)
        guard let data = try? Data(contentsOf: url) else { return DayLog(day: day, wakeMinute: wakeMinute) }
        guard let log = try? JSONDecoder().decode(DayLog.self, from: data) else {
            try? FileManager.default.moveItem(
                at: url, to: directory.appending(path: "\(day).\(Int(Date().timeIntervalSince1970)).unreadable"))
            return DayLog(day: day, wakeMinute: wakeMinute)
        }
        return log
    }

    /// The days with logs saved, oldest first.
    public func savedDays() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent }
            .filter { DayID.date($0) != nil }.sorted()
    }

    public func save(_ log: DayLog) throws {
        try JSONEncoder().encode(log).write(to: url(for: log.day), options: .atomic)
    }

    private func url(for day: String) -> URL {
        directory.appending(path: "\(day).json")
    }
}
