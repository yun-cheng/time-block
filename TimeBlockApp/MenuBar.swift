import SwiftUI
import TimeBlockKit
import TimeBlockUI

#if os(macOS)
import AppKit

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

/// Today at a glance, as the window kept on top shows it: the counter, all the day's blocks and the timers, with Start
/// Timer opening the timer dialog over it.
struct MenuBarPanel: View {
    @Bindable var model: AppModel
    @State private var showsTimerStarter = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let snapshot = model.snapshot
        let theme = MoodTheme(mood: snapshot.mood, colorScheme: colorScheme)
        VStack(spacing: 0) {
            TimelineView(.animation(minimumInterval: 1.0 / 15)) { context in
                DayView(
                    snapshot: model.snapshot(at: context.date),
                    time: context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000),
                    timers: model.timerControls, date: context.date, isCompact: true,
                    controls: DayControls(timer: { AnyView(StartTimerButton(theme: $0, isOpen: $showsTimerStarter)) }))
            }
            .overlay {
                if showsTimerStarter {
                    TimerDialog(model: model, theme: theme, isCompact: true, isOpen: $showsTimerStarter)
                }
            }
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
        .frame(width: DayView.compactWidth(of: snapshot))
    }
}
#endif

extension AppModel {
    /// The timers, to show and change in the window and the menu bar.
    var timerControls: TimerControls {
        TimerControls(
            timers: timers, countdown: Binding { self.countdownMinutes } set: { self.countdownMinutes = $0 },
            presets: countdownPresets, start: startTimer, stop: stopTimer, delete: deleteTimer)
    }
}
