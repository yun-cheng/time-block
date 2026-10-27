import AppIntents
import SwiftUI
import TimeBlockKit
import TimeBlockUI
import WidgetKit

/// The view a widget shows, chosen in the widget's Edit sheet.
enum ViewOption: String, AppEnum {
    case activity, body

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "View"
    static let caseDisplayRepresentations: [ViewOption: DisplayRepresentation] = [
        // App Intents reads these at build time, so symbol names must be literals (matching `Track.symbol`).
        .activity: DisplayRepresentation(title: "Activity", image: .init(systemName: "square.grid.3x3.fill")),
        .body: DisplayRepresentation(title: "Body", image: .init(systemName: "figure.walk")),
    ]

    var track: Track {
        switch self {
        case .activity: .activity
        case .body: .body
        }
    }
}

struct ViewIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose View"
    static let description = IntentDescription("Show what you did, or what your body did.")

    @Parameter(title: "View", default: .activity)
    var view: ViewOption
}

struct DayEntry: TimelineEntry {
    let date: Date
    let snapshot: DaySnapshot
}

struct DayProvider: AppIntentTimelineProvider {
    /// 12 hours of 5-minute entries. Precomputed entries don't count against WidgetKit's reload budget;
    /// the app reloads the timeline whenever settings change.
    private static let entryCount = 12 * Schedule.blocksPerHour

    func placeholder(in context: Context) -> DayEntry {
        DayEntry(date: .now, snapshot: Self.sample(at: .now, track: .activity))
    }

    func snapshot(for configuration: ViewIntent, in context: Context) async -> DayEntry {
        // The widget gallery shows a filled-in day rather than an empty one.
        let track = configuration.view.track
        if context.isPreview { return DayEntry(date: .now, snapshot: Self.sample(at: .now, track: track)) }
        let settings = SettingsStore.load()
        let log = Self.log(of: settings.dayID(for: .now), settings: settings)
        return DayEntry(date: .now, snapshot: settings.snapshot(at: .now, log: log, track: track, timers: TimerStore.load()))
    }

    func timeline(for configuration: ViewIntent, in context: Context) async -> Timeline<DayEntry> {
        let settings = SettingsStore.load()
        // Timers going are drawn as running on, until the app says they've stopped.
        let timers = TimerStore.load()
        var logs: [String: DayLog] = [:]
        let entries = BlockClock.boundaries(from: .now, count: Self.entryCount).map { date in
            let day = settings.dayID(for: date)
            let log = logs[day] ?? Self.log(of: day, settings: settings)
            logs[day] = log
            return DayEntry(
                date: date, snapshot: settings.snapshot(at: date, log: log, track: configuration.view.track, timers: timers))
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    /// The saved logs of `day`, with its routines laid out as the app lays them out the first time it sees the day,
    /// which it may not have yet: the day has just come, and the app isn't running.
    private static func log(of day: String, settings: AppSettings) -> DayLog {
        let schedule = settings.schedule(on: day)
        var log = LogStore.shared.load(day: day, wakeMinute: schedule.wakeMinute)
        if !log.isPlanned { log.plan(settings.templates, schedule: schedule, categories: settings.categories) }
        return log
    }

    private static func sample(at date: Date, track: Track) -> DaySnapshot {
        let schedule = Schedule.standard
        return SampleDay.snapshot(schedule: schedule, nowMinute: schedule.timelineMinute(for: date), track: track)
    }
}

struct DayWidgetView: View {
    let entry: DayEntry
    @Environment(\.widgetFamily) private var widgetFamily
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = MoodTheme(mood: entry.snapshot.mood, colorScheme: colorScheme)
        WidgetContent(family: family, snapshot: entry.snapshot, theme: theme)
            .containerBackground(for: .widget) { MoodBackground(theme: theme) }
    }

    private var family: WidgetContent.Family {
        switch widgetFamily {
        case .systemSmall: .small
        case .systemMedium: .medium
        default: .large
        }
    }
}

struct DayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "DayWidget", intent: ViewIntent.self, provider: DayProvider()) { entry in
            DayWidgetView(entry: entry)
        }
        .configurationDisplayName("Time Block")
        .description("Your waking day in 5-minute blocks. Edit the widget to switch between Activity and Body.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        // The content views bring their own padding; the small ring wants to sit close to the edge.
        .contentMarginsDisabled()
    }
}

@main
struct TimeBlockWidgetBundle: WidgetBundle {
    var body: some Widget {
        DayWidget()
    }
}
