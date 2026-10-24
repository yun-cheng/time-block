import SwiftUI
import TimeBlockKit

/// macOS desktop widget sizes, so previews match what WidgetKit gives the real widget.
public enum WidgetMockSize: CaseIterable, Sendable {
    case small, medium, large

    public var size: CGSize {
        switch self {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 364, height: 170)
        case .large: CGSize(width: 364, height: 382)
        }
    }
}

/// Background, size and rounded corners of a desktop widget, for previewing outside WidgetKit.
struct WidgetChrome<Content: View>: View {
    let theme: MoodTheme
    let size: WidgetMockSize
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: size.size.width, height: size.size.height)
            .background(MoodBackground(theme: theme))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}

/// A widget's content without its background. The real widget puts `MoodBackground` in its
/// container background; previews wrap it in `WidgetChrome`. Each content view brings its own padding.
public struct WidgetContent: View {
    public enum Family: Sendable { case small, medium, large }

    let family: Family
    let snapshot: DaySnapshot
    let theme: MoodTheme

    public init(family: Family, snapshot: DaySnapshot, theme: MoodTheme) {
        self.family = family
        self.snapshot = snapshot
        self.theme = theme
    }

    public var body: some View {
        switch family {
        case .small: small
        case .medium: medium
        case .large: large
        }
    }

    /// Ring of the day with the counter in the middle.
    private var small: some View {
        ZStack {
            DayRingView(snapshot: snapshot, theme: theme)
            VStack(spacing: 0) {
                if snapshot.track != .activity {
                    Image(systemName: snapshot.track.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                }
                CounterView(value: snapshot.status.blocksLeft, theme: theme, size: 36, total: snapshot.status.schedule.awakeBlocks)
                Text(MoodCopy.caption(snapshot.mood))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 30)
        }
        .padding(8)
    }

    /// Counter and current activity, with the hours around now.
    private var medium: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                CounterView(value: snapshot.status.blocksLeft, theme: theme, size: 44, total: snapshot.status.schedule.awakeBlocks)
                Text(MoodCopy.caption(snapshot.mood))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                Spacer(minLength: 0)
                NowChip(snapshot: snapshot, theme: theme)
                StatsLine(snapshot: snapshot, theme: theme)
            }
            .frame(width: 118, alignment: .leading)
            BlockGridView(snapshot: snapshot, theme: theme, rows: BlockGridView.rows(around: snapshot, count: 5))
        }
        .padding(14)
    }

    /// The whole day.
    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                CounterView(value: snapshot.status.blocksLeft, theme: theme, size: 38, total: snapshot.status.schedule.awakeBlocks)
                Text(MoodCopy.caption(snapshot.mood))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                Spacer(minLength: 0)
                NowChip(snapshot: snapshot, theme: theme)
            }
            BlockGridView(snapshot: snapshot, theme: theme)
            StoryBar(snapshot: snapshot, theme: theme)
            if let line = MoodCopy.line(snapshot.mood) {
                Text(line)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Legend(snapshot: snapshot, theme: theme, limit: 4)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(16)
    }
}

/// A widget as it looks on the desktop, for the prototype and renders.
public struct WidgetMock: View {
    let size: WidgetMockSize
    let snapshot: DaySnapshot
    @Environment(\.colorScheme) private var colorScheme

    public init(_ size: WidgetMockSize, snapshot: DaySnapshot) {
        self.size = size
        self.snapshot = snapshot
    }

    public var body: some View {
        let theme = MoodTheme(mood: snapshot.mood, colorScheme: colorScheme)
        WidgetChrome(theme: theme, size: size) {
            WidgetContent(family: size.family, snapshot: snapshot, theme: theme)
        }
    }
}

extension WidgetMockSize {
    var family: WidgetContent.Family {
        switch self {
        case .small: .small
        case .medium: .medium
        case .large: .large
        }
    }
}

struct NowChip: View {
    let snapshot: DaySnapshot
    let theme: MoodTheme

    var body: some View {
        if snapshot.currentCell?.isOvertime == true {
            Label("Go to sleep", systemImage: "moon.zzz.fill")
                .foregroundStyle(theme.accent)
                .font(.system(size: 11, weight: .semibold))
        } else if let category = snapshot.currentCategory {
            Label(category.name, systemImage: category.symbol)
                .foregroundStyle(theme.color(of: category))
                .font(.system(size: 11, weight: .semibold))
        } else {
            Label("Unlogged", systemImage: "questionmark.square.dashed")
                .foregroundStyle(theme.secondaryText)
                .font(.system(size: 11, weight: .semibold))
        }
    }
}

struct StatsLine: View {
    let snapshot: DaySnapshot
    let theme: MoodTheme

    var body: some View {
        Text("\(snapshot.status.blocksUsed) used · \(snapshot.loggedCount) logged")
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(theme.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// Where the day went: "Focus 5h 10m" in Activity, "Sitting 6h" in Body.
struct Legend: View {
    let snapshot: DaySnapshot
    let theme: MoodTheme
    var limit: Int
    var fontSize: CGFloat = 10

    var body: some View {
        HStack(spacing: fontSize * 0.9) {
            ForEach(snapshot.legendTotals.prefix(limit)) { total in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(rgb: theme.grade(total.color)))
                        .frame(width: fontSize * 0.7, height: fontSize * 0.7)
                    Text(total.name)
                        .font(.system(size: fontSize, weight: .semibold))
                        .foregroundStyle(theme.text)
                    Text(durationText(blocks: total.blocks))
                        .font(.system(size: fontSize, weight: .medium).monospacedDigit())
                        .foregroundStyle(theme.secondaryText)
                }
                .lineLimit(1)
            }
        }
        .minimumScaleFactor(0.75)
    }
}

/// The day so far as one bar split like the legend, then unlogged time, then time taken from sleep.
struct StoryBar: View {
    let snapshot: DaySnapshot
    let theme: MoodTheme

    private struct Segment: Identifiable {
        let id: String
        let blocks: Int
        let color: Color
    }

    var body: some View {
        let segments =
            snapshot.legendTotals.map { Segment(id: $0.id, blocks: $0.blocks, color: Color(rgb: theme.grade($0.color))) }
            + [
                Segment(id: "unlogged", blocks: snapshot.unloggedCount, color: theme.unloggedBlock),
                Segment(id: "overtime", blocks: snapshot.pastOvertimeCount, color: theme.overtimeBlock),
            ].filter { $0.blocks > 0 }
        let total = max(1, segments.reduce(0) { $0 + $1.blocks })

        GeometryReader { proxy in
            let spacing: CGFloat = 2
            let width = proxy.size.width - spacing * CGFloat(max(0, segments.count - 1))
            HStack(spacing: spacing) {
                ForEach(segments) { segment in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(segment.color)
                        .frame(width: width * CGFloat(segment.blocks) / CGFloat(total))
                }
            }
        }
        .frame(height: 10)
    }
}

/// "1h 25m" for 17 blocks.
public func durationText(blocks: Int) -> String {
    let minutes = blocks * Schedule.blockMinutes
    let (h, m) = (minutes / 60, minutes % 60)
    if h == 0 { return "\(m)m" }
    return m == 0 ? "\(h)h" : "\(h)h \(m)m"
}
