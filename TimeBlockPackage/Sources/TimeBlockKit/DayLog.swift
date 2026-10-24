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

    public init(day: String, wakeMinute: Int, logs: [BlockLog] = []) {
        self.day = day
        self.wakeMinute = wakeMinute
        self.logs = logs
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
    /// when clearing) change: parts outside `range` are kept, and runs of one category join up.
    public mutating func set(
        _ range: Range<Int>, to categoryID: String?, in track: Track, schedule: Schedule,
        categories: [BlockCategory] = BlockCategory.defaults
    ) {
        guard !range.isEmpty else { return }
        logs = logs(for: schedule)
        wakeMinute = schedule.wakeMinute

        let trackOf = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.track) })
        var kept: [BlockLog] = []
        for log in logs {
            guard trackOf[log.categoryID] == track, log.range.overlaps(range) else {
                kept.append(log)
                continue
            }
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
        if let categoryID {
            kept.append(BlockLog(startIndex: range.lowerBound, length: range.count, categoryID: categoryID))
        }

        var joined: [BlockLog] = []
        for log in kept.sorted(by: { $0.startIndex < $1.startIndex }) {
            if let i = joined.lastIndex(where: {
                $0.range.upperBound == log.startIndex && $0.categoryID == log.categoryID
                    && $0.source == log.source && $0.note == log.note
            }) {
                joined[i].length += log.length
            } else {
                joined.append(log)
            }
        }
        logs = joined
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
