import SwiftUI
import TimeBlockKit

/// Starts and stops the timers that log activities live.
public struct TimerControls {
    public var timers: [LiveTimer]
    /// What new timers count down from, in minutes, or nil to count up.
    public var countdown: Binding<Int?>
    /// Starts a timer of an activity, unless it has one going.
    public var start: (String) -> Void
    /// Stops a timer, logging what it ran.
    public var stop: (UUID) -> Void
    /// Drops a timer without logging what it ran.
    public var delete: (UUID) -> Void

    public init(
        timers: [LiveTimer], countdown: Binding<Int?>, start: @escaping (String) -> Void,
        stop: @escaping (UUID) -> Void, delete: @escaping (UUID) -> Void
    ) {
        self.timers = timers
        self.countdown = countdown
        self.start = start
        self.stop = stop
        self.delete = delete
    }

    /// The countdowns to pick from, in minutes; 25 is a Pomodoro.
    static let countdowns = [5, 10, 15, 20, 25, 30, 45, 50, 60, 90]
}

/// The timers going, each with its activity, its time (counting up, or down and then on past zero, in the accent
/// color) and buttons to stop it and to delete it.
public struct TimerList: View {
    let controls: TimerControls
    let categories: [String: BlockCategory]
    let theme: MoodTheme
    let date: Date
    /// The timer whose delete is waiting to be confirmed.
    @State private var deleting: LiveTimer?

    public init(controls: TimerControls, categories: [String: BlockCategory], theme: MoodTheme, date: Date) {
        self.controls = controls
        self.categories = categories
        self.theme = theme
        self.date = date
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(controls.timers) { timer in
                row(timer)
            }
        }
        .alert(
            "Delete the \(deleting.map { name(of: $0) } ?? "") timer?",
            isPresented: Binding { deleting != nil } set: { if !$0 { deleting = nil } },
            presenting: deleting
        ) { timer in
            Button("Delete", role: .destructive) { controls.delete(timer.id) }
            Button("Cancel", role: .cancel) {}
        } message: { timer in
            Text("The \(Self.clock(timer.elapsed(at: .now))) it has run won't be logged.")
        }
    }

    private func name(of timer: LiveTimer) -> String {
        categories[timer.categoryID]?.name ?? timer.categoryID
    }

    private func row(_ timer: LiveTimer) -> some View {
        let category = categories[timer.categoryID]
        let remaining = timer.remaining(at: date)
        let isOver = (remaining ?? 0) < 0
        return HStack(spacing: 8) {
            Label(name(of: timer), systemImage: category?.symbol ?? "questionmark")
                .foregroundStyle(category.map { theme.color(of: $0) } ?? theme.text)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: timer.countdown == nil ? "stopwatch" : "timer")
                .foregroundStyle(theme.secondaryText)
                .help(timer.countdown.map { "Counting down from \(Int($0) / 60) min" } ?? "Counting up")
            Text(Self.clock(remaining ?? timer.elapsed(at: date)))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(isOver ? theme.accent : theme.text)
                .help(isOver ? "Over its countdown" : "")
            Button {
                controls.stop(timer.id)
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 16)
            }
            .help("Stop")
            Button {
                deleting = timer
            } label: {
                Image(systemName: "trash")
                    .frame(width: 16)
            }
            .help("Delete: drop it, leaving what it ran unlogged")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(theme.text)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(theme.text.opacity(0.07)))
    }

    /// "4:07", "1:02:03", or "−2:13" past zero.
    static func clock(_ interval: TimeInterval) -> String {
        let seconds = Int(abs(interval).rounded(.down))
        let sign = interval <= -1 ? "\u{2212}" : ""
        let (hours, minutes) = (seconds / 3600, seconds / 60 % 60)
        return hours > 0
            ? String(format: "%@%d:%02d:%02d", sign, hours, minutes, seconds % 60)
            : String(format: "%@%d:%02d", sign, minutes, seconds % 60)
    }
}

/// Starts a timer: pick how it counts, then the activity to time. The timers going are listed apart, so no chip is
/// lit.
public struct TimerStarter: View {
    let controls: TimerControls
    let snapshot: DaySnapshot
    let theme: MoodTheme

    public init(controls: TimerControls, snapshot: DaySnapshot, theme: MoodTheme) {
        self.controls = controls
        self.snapshot = snapshot
        self.theme = theme
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Start a timer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                CountdownPicker(countdown: controls.countdown)
            }
            CategoryPalette(
                categories: snapshot.trackCategories, favorites: snapshot.favorites,
                selected: [], theme: theme, showsClear: false,
                choose: { if let id = $0.categoryID { controls.start(id) } })
        }
    }
}

/// How new timers count: up from zero, or down from a length and on past it.
struct CountdownPicker: View {
    let countdown: Binding<Int?>

    var body: some View {
        Picker("Counts", selection: countdown) {
            Label("Count up", systemImage: "stopwatch").tag(Int?.none)
            Divider()
            ForEach(TimerControls.countdowns, id: \.self) { minutes in
                Label("Count down \(minutes) min", systemImage: "timer").tag(Int?.some(minutes))
            }
        }
        .labelsHidden()
        .fixedSize()
        .help("How new timers count: up from zero, or down from a length and on past it")
    }
}
