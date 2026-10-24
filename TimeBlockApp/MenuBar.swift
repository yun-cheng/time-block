import AppKit
import SwiftUI
import TimeBlockKit
import TimeBlockUI

/// "▦ 92/192" in the menu bar. Menu bar items are monochrome, so the symbol carries the mood.
struct MenuBarLabel: View {
    let snapshot: DaySnapshot

    var body: some View {
        let status = snapshot.status
        let count = status.blocksLeft < 0 ? "\u{2212}\(-status.blocksLeft)" : "\(status.blocksLeft)"
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text("\(count)/\(status.schedule.awakeBlocks)").monospacedDigit()
        }
    }

    private var symbol: String {
        switch snapshot.mood {
        case .calm: "square.grid.3x3.fill"
        case .windDown: "moon.fill"
        case .uneasy: "moon.zzz.fill"
        case .dread, .nightmare: "exclamationmark.triangle.fill"
        }
    }
}

struct MenuBarPanel: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let snapshot = model.snapshot
        let theme = MoodTheme(mood: snapshot.mood, colorScheme: colorScheme)
        VStack(spacing: 0) {
            WidgetContent(family: .medium, snapshot: snapshot, theme: theme)
                .frame(height: 170)
                .background(MoodBackground(theme: theme))
            Divider()
            NowLogger(model: model, snapshot: snapshot, theme: theme)
                .padding(12)
            Divider()
            HStack {
                TrackPicker(track: $model.settings.track)
                    .fixedSize()
                Spacer()
                Button {
                    openWindow(id: "main")
                    NSApp.activate()
                } label: {
                    Image(systemName: "macwindow")
                }
                .help("Open Time Block")
                Button {
                    showSettings(model, openWindow: openWindow)
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit Time Block")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 364)
    }
}

/// Logs the block in progress with one click.
struct NowLogger: View {
    @Bindable var model: AppModel
    let snapshot: DaySnapshot
    let theme: MoodTheme

    var body: some View {
        if let current = snapshot.status.currentIndex {
            let schedule = snapshot.status.schedule
            let gap = snapshot.unloggedRun(before: current)
            VStack(alignment: .leading, spacing: 8) {
                Text("Now, \(clock(schedule.clockMinute(ofBlock: current)))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 8) {
                    ForEach(snapshot.trackCategories) { category in
                        CategoryChip(
                            category: category, theme: theme, isSelected: snapshot.currentCell?.categoryID == category.id
                        ) {
                            model.logNow(category.id)
                        }
                    }
                }
                .padding(3)
                if !gap.isEmpty {
                    Toggle(isOn: $model.fillsGap) {
                        Text("Also fill \(durationText(blocks: gap.count)) unlogged since \(clock(schedule.clockMinute(ofBlock: gap.lowerBound)))")
                    }
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Logging starts at \(clock(snapshot.status.schedule.wakeMinute)).")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}
