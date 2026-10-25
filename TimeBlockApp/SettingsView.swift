import AppKit
import SwiftUI
import TimeBlockKit

/// Settings live in the main window's inspector, not a separate window.
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        let schedule = model.settings.schedule
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

    /// While a sleep shift runs, the schedule is where it's heading rather than today's.
    private var shiftNote: String {
        guard model.settings.sleepShift != nil else { return "" }
        let today = model.schedule
        return String(format: " A sleep shift is getting you here: today is %02d:%02d–%02d:%02d.",
                      today.wakeMinute / 60, today.wakeMinute % 60, today.bedMinute / 60, today.bedMinute % 60)
    }

    /// Edits one of the schedule's minute-of-day fields with a time picker, snapped to 5 minutes.
    private func minuteBinding(_ field: WritableKeyPath<Schedule, Int>) -> Binding<Date> {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: .now)
        return Binding {
            midnight.addingTimeInterval(Double(model.settings.schedule[keyPath: field] * 60))
        } set: { date in
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            var schedule = model.settings.schedule
            schedule[keyPath: field] = Schedule.snappedMinute(editing: schedule[keyPath: field], to: minute)
            // Rebuild so the day's rollover point follows the new wake time.
            model.settings.schedule = Schedule(wakeMinute: schedule.wakeMinute, bedMinute: schedule.bedMinute)
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
