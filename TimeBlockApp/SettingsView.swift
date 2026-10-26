import AppKit
import SwiftUI
import TimeBlockKit
import TimeBlockUI

/// Settings live in a panel beside the main window's day, not a separate window.
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        // Today's times, which a sleep shift moves day by day.
        let schedule = model.schedule
        Form {
            Section {
                TimeField("Wake up", minute: minuteBinding(\.wakeMinute))
                    // On a row, since the form's scroll view is around its rows rather than the form.
                    .appScrollBar()
                TimeField("Bedtime", minute: minuteBinding(\.bedMinute))
                Picker("Wind down", selection: $model.settings.windDownMinutes) {
                    ForEach([15, 30, 45, 60, 90, 120], id: \.self) { minutes in
                        Text(durationText(blocks: minutes / Schedule.blockMinutes)).tag(minutes)
                    }
                    Text("None").tag(0)
                }
                .help("Time before bedtime to get ready for sleep. The grid tints it, and the day turns warm when it starts.")
                LabeledContent("Usable blocks") {
                    Text("\(schedule.awakeBlocks) · \(durationText(blocks: schedule.awakeBlocks))")
                        .monospacedDigit()
                }
            } header: {
                Text("Schedule")
            } footer: {
                if isShifting {
                    Text("Today's times, on a sleep shift.")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Grid") {
                Picker("Minute gaps", selection: $model.settings.grid.gapMinutes) {
                    ForEach([10, 15, 20, 30], id: \.self) { minutes in
                        Text("Every \(minutes) minutes").tag(minutes)
                    }
                    Text("None").tag(0)
                }
                Picker("Minute numbers", selection: $model.settings.grid.labelMinutes) {
                    ForEach([10, 15, 20, 30], id: \.self) { minutes in
                        Text("Every \(minutes) minutes").tag(minutes)
                    }
                    Text("None").tag(0)
                }
                Picker("Hour gaps", selection: $model.settings.grid.hourGaps) {
                    Text("On the clock").tag(GridMarks.HourGaps.clock)
                    Text("Dividing the day").tag(GridMarks.HourGaps.divided)
                    Text("None").tag(GridMarks.HourGaps.none)
                }
                switch model.settings.grid.hourGaps {
                case .clock:
                    Picker("Every", selection: $model.settings.grid.gapHours) {
                        ForEach([3, 6, 12], id: \.self) { hours in
                            Text("\(hours) hours").tag(hours)
                        }
                    }
                case .divided:
                    Picker("Into", selection: $model.settings.grid.dayParts) {
                        ForEach(2...6, id: \.self) { parts in
                            Text("\(parts) parts").tag(parts)
                        }
                    }
                case .none:
                    EmptyView()
                }
            }
            SleepShiftSettings(model: model)
            TemplateSettings(model: model)
            ActivitySettings(model: model)
        }
        .formStyle(.grouped)
    }

    /// Whether a sleep shift has started moving today's times, which it carries on from.
    private var isShifting: Bool {
        guard let shift = model.settings.sleepShift else { return false }
        return (DayID.days(from: model.dayLog.day, to: shift.startDay) ?? 0) <= 0
    }

    /// One of today's minute-of-day fields.
    private func minuteBinding(_ field: WritableKeyPath<Schedule, Int>) -> Binding<Int> {
        Binding {
            model.schedule[keyPath: field]
        } set: { minute in
            var schedule = model.schedule
            schedule[keyPath: field] = minute
            // Rebuild so the day's rollover point follows the new wake time.
            model.setSchedule(Schedule(wakeMinute: schedule.wakeMinute, bedMinute: schedule.bedMinute))
        }
    }
}

/// Opens the main window with its settings showing.
@MainActor
func showSettings(_ model: AppModel, openWindow: OpenWindowAction) {
    // Settings need the whole window.
    model.isPinned = false
    model.showsSettings = true
    openWindow(id: "main")
    NSApp.activate()
}

/// Time Block ▸ Settings… (⌘,) shows the settings panel instead of a separate Settings window.
struct SettingsCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { showSettings(model, openWindow: openWindow) }
                .keyboardShortcut(",", modifiers: .command)
        }
    }
}
