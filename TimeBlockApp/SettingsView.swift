import SwiftUI
import TimeBlockKit

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        let schedule = model.settings.schedule
        Form {
            Section {
                DatePicker("Wake up", selection: minuteBinding(\.wakeMinute), displayedComponents: .hourAndMinute)
                DatePicker("Bedtime", selection: minuteBinding(\.bedMinute), displayedComponents: .hourAndMinute)
                LabeledContent("Usable blocks") {
                    Text("\(schedule.awakeBlocks)  (\(schedule.awakeBlocks / 12)h \(schedule.awakeBlocks % 12 * 5)m awake)")
                        .monospacedDigit()
                }
            } header: {
                Text("Schedule")
            } footer: {
                Text("Times snap to 5-minute blocks. A bedtime before your wake time means after midnight.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show a sample day", isOn: $model.settings.showsSampleLogs)
            } footer: {
                Text("Fills the grid with example logs until logging arrives in the next milestone.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
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
            schedule[keyPath: field] = minute / Schedule.blockMinutes * Schedule.blockMinutes
            // Rebuild so the day's rollover point follows the new wake time.
            model.settings.schedule = Schedule(wakeMinute: schedule.wakeMinute, bedMinute: schedule.bedMinute)
        }
    }
}
