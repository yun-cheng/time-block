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
            NowTimers(model: model, snapshot: snapshot, theme: theme)
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

/// Times what you're doing now: the timers going, and a palette that starts one.
struct NowTimers: View {
    let model: AppModel
    let snapshot: DaySnapshot
    let theme: MoodTheme

    var body: some View {
        let controls = model.timerControls
        VStack(alignment: .leading, spacing: 10) {
            if !controls.timers.isEmpty {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    TimerList(controls: controls, categories: snapshot.categories, theme: theme, date: context.date)
                }
            }
            if snapshot.status.currentIndex != nil {
                TimerStarter(controls: controls, snapshot: snapshot, theme: theme)
            } else {
                Text("Logging starts at \(clock(snapshot.status.schedule.wakeMinute)).")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

extension AppModel {
    /// The timers, to show and change in the window and the menu bar.
    var timerControls: TimerControls {
        TimerControls(
            timers: timers, countdown: Binding { self.countdownMinutes } set: { self.countdownMinutes = $0 },
            presets: countdownPresets, start: startTimer, stop: stopTimer, delete: deleteTimer)
    }
}
