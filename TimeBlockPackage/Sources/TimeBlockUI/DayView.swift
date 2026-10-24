import SwiftUI
import TimeBlockKit

/// The main app's day screen. Unlike widgets, it animates.
public struct DayView: View {
    let snapshot: DaySnapshot
    var time: Double
    @Environment(\.colorScheme) private var colorScheme

    public init(snapshot: DaySnapshot, time: Double = 0) {
        self.snapshot = snapshot
        self.time = time
    }

    private var clockLabel: String {
        let minute = snapshot.status.nowMinute % (24 * 60)
        return String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    public var body: some View {
        let theme = MoodTheme(mood: snapshot.mood, colorScheme: colorScheme)
        let status = snapshot.status
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Label("\(snapshot.track.name) · \(clockLabel)", systemImage: snapshot.track.symbol)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                    CounterView(value: status.blocksLeft, theme: theme, size: 64, total: status.schedule.awakeBlocks, time: time)
                    Text(MoodCopy.caption(snapshot.mood))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    stat("\(status.schedule.awakeBlocks)", "usable", theme)
                    stat("\(status.blocksUsed)", "used", theme)
                    stat("\(snapshot.loggedCount)", "logged", theme)
                    if let longestSit = snapshot.longestSit {
                        stat(durationText(blocks: longestSit), "longest sit", theme)
                    }
                    if status.overtimeBlocks > 0 {
                        stat("\(status.overtimeBlocks)", "over", theme, color: theme.accent)
                    }
                }
            }
            if let line = MoodCopy.line(snapshot.mood) {
                Text(line)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.accent)
            }
            BlockGridView(snapshot: snapshot, theme: theme, time: time)
            NowChip(snapshot: snapshot, theme: theme)
            StoryBar(snapshot: snapshot, theme: theme)
            Legend(snapshot: snapshot, theme: theme, limit: 4, fontSize: 11)
        }
        .padding(22)
        .background(MoodBackground(theme: theme, time: time))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func stat(_ value: String, _ label: String, _ theme: MoodTheme, color: Color? = nil) -> some View {
        HStack(spacing: 4) {
            Text(value).font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundStyle(color ?? theme.text)
            Text(label).font(.system(size: 12)).foregroundStyle(theme.secondaryText)
        }
    }
}
