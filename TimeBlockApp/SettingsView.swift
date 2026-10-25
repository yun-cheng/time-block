import AppKit
import SwiftUI
import TimeBlockKit

/// Settings live in the main window's inspector, not a separate window.
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        // Today's times, which a sleep shift moves day by day.
        let schedule = model.schedule
        Form {
            Section {
                DatePicker("Wake up", selection: minuteBinding(\.wakeMinute), displayedComponents: .hourAndMinute)
                    // On a row, since the form's scroll view is around its rows rather than the form.
                    .appScrollBar()
                DatePicker("Bedtime", selection: minuteBinding(\.bedMinute), displayedComponents: .hourAndMinute)
                LabeledContent("Usable blocks") {
                    Text("\(schedule.awakeBlocks)")
                        .monospacedDigit()
                }
            } header: {
                Text("Schedule")
            } footer: {
                Text("\(schedule.awakeBlocks / 12)h \(schedule.awakeBlocks % 12 * 5)m awake. Times snap to 5-minute blocks. A bedtime before your wake time means after midnight.\(shiftNote)")
                    .foregroundStyle(.secondary)
            }
            SleepShiftSettings(model: model)
            TemplateSettings(model: model)
            ActivitySettings(model: model)
        }
        .formStyle(.grouped)
    }

    /// With a sleep shift, these are today's times and it carries on from them.
    private var shiftNote: String {
        guard let shift = model.settings.sleepShift else { return "" }
        let target = model.settings.schedule
        let heading = String(format: "%02d:%02d–%02d:%02d", target.wakeMinute / 60, target.wakeMinute % 60,
                             target.bedMinute / 60, target.bedMinute % 60)
        let today = model.dayLog.day
        guard (DayID.days(from: today, to: shift.startDay) ?? 0) > 0 else {
            return " These are today's times on a sleep shift heading to \(heading). Change them, say after sleeping in, and it carries on from them tomorrow night."
        }
        let start = SleepShiftSettings.dayName(shift.startDay, today: today)
        let night = start == "Tomorrow" ? "tomorrow night" : "the night of \(start)"
        return " A sleep shift heading to \(heading) moves on from these times \(night)."
    }

    /// Edits one of today's minute-of-day fields with a time picker, snapped to 5 minutes.
    private func minuteBinding(_ field: WritableKeyPath<Schedule, Int>) -> Binding<Date> {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: .now)
        return Binding {
            midnight.addingTimeInterval(Double(model.schedule[keyPath: field] * 60))
        } set: { date in
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            var schedule = model.schedule
            schedule[keyPath: field] = Schedule.snappedMinute(editing: schedule[keyPath: field], to: minute)
            // Rebuild so the day's rollover point follows the new wake time.
            model.setSchedule(Schedule(wakeMinute: schedule.wakeMinute, bedMinute: schedule.bedMinute))
        }
    }
}

/// Opens the main window with its settings inspector showing.
@MainActor
func showSettings(_ model: AppModel, openWindow: OpenWindowAction) {
    model.showsSettings = true
    openWindow(id: "main")
    NSApp.activate()
}

/// Time Block ▸ Settings… (⌘,) shows the inspector instead of a separate Settings window.
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
