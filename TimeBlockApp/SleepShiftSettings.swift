import SwiftUI
import TimeBlockKit

/// Moves your schedule to new times a step at a time, like 30 minutes a day, instead of all at once. While a shift
/// runs, the schedule above is where it's heading and each day's grid uses that day's step.
struct SleepShiftSettings: View {
    @Bindable var model: AppModel
    @State private var isEditing = false

    var body: some View {
        Section {
            if isEditing {
                SleepShiftEditor(model: model, done: { isEditing = false })
                    .background { ScrollIntoView() }
            } else if let shift = model.settings.sleepShift {
                running(shift)
            } else {
                Button("Shift Gradually…", systemImage: "moon.zzz") { isEditing = true }
            }
        } header: {
            Text("Sleep Shift")
        }
    }

    private func running(_ shift: SleepShift) -> some View {
        let target = model.settings.schedule
        let today = model.dayLog.day
        let steps = Self.changes(of: shift, target: target, after: today)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "moon.zzz")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Heading to \(times(target))")
                        .monospacedDigit()
                    Text(Self.summary(of: shift, target: target, today: model.schedule))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if !steps.isEmpty {
                let names = steps.map { "\(Self.dayName($0.day, today: today)) \(times($0.schedule))" }
                // The first few and the last.
                Text((names.count > 5 ? names.prefix(3) + ["…", names[names.count - 1]] : names[...]).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.leading, 28)
            }
            HStack {
                if shift.movesOnNight(of: today, target: target) {
                    Button("Hold Tonight") {
                        model.resumeSleepShift(nextStepOn: DayID.adding(1, to: today) ?? today)
                    }
                    .help("Keep last night's bedtime tonight and tomorrow's wake time, and take each step a night later")
                } else {
                    let next = Self.dayName(shift.nextStepDay(from: today), today: today, on: true)
                    Button("Step Tonight") { model.resumeSleepShift(nextStepOn: today) }
                        .help("Take the next step tonight instead of \(next)")
                }
                Spacer()
                Button("Edit…") { isEditing = true }
                Button("Stop Shift") { model.stopSleepShift() }
                    .help("Keep today's times as your schedule")
            }
        }
    }

    /// "Today 11:30–02:30 · 30 min earlier every day".
    static func summary(of shift: SleepShift, target: Schedule, today: Schedule) -> String {
        let wake = SleepShift.distance(from: shift.from.wakeMinute, to: target.wakeMinute)
        let bed = SleepShift.distance(from: shift.from.bedMinute, to: target.bedMinute)
        let direction = (abs(bed) >= abs(wake) ? bed : wake) < 0 ? "earlier" : "later"
        let every = shift.everyDays == 1 ? "every day" : "every \(shift.everyDays) days"
        return "Today \(times(today)) · \(shift.stepMinutes) min \(direction) \(every)"
    }

    /// Each day after `today` whose schedule is new, up to the one that's all on `target`.
    static func changes(of shift: SleepShift, target: Schedule, after today: String) -> [(day: String, schedule: Schedule)] {
        let days = DayID.days(from: today, to: shift.finishDay(target: target)) ?? 0
        guard days > 0 else { return [] }
        var previous = shift.schedule(on: today, target: target)
        return (1...days).compactMap { offset in
            guard let day = DayID.adding(offset, to: today) else { return nil }
            let schedule = shift.schedule(on: day, target: target)
            defer { previous = schedule }
            return schedule == previous ? nil : (day, schedule)
        }
    }

    /// "Tomorrow", "Thu", or "Thu 5 Nov" a week or more out; "on Thu" with `on`.
    static func dayName(_ day: String, today: String, on: Bool = false) -> String {
        let days = DayID.days(from: today, to: day) ?? 0
        guard let date = DayID.date(day) else { return day }
        switch days {
        case ...0: return on ? "today" : "Today"
        case 1: return on ? "tomorrow" : "Tomorrow"
        case 2..<7: return (on ? "on " : "") + date.formatted(.dateTime.weekday(.abbreviated))
        default: return (on ? "on " : "") + date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
    }
}

/// "07:00–23:00".
private func times(_ schedule: Schedule) -> String {
    "\(Schedule.clockText(schedule.wakeMinute))–\(Schedule.clockText(schedule.bedMinute))"
}

/// Sets up a shift, or changes the one under way from tonight on: the bedtime or wake time to get to, how big and
/// how often the steps are, and the night they start or the day to be there by.
private struct SleepShiftEditor: View {
    @Bindable var model: AppModel
    let done: () -> Void

    private enum Timing: Hashable {
        case start, finish
    }

    @State private var end = Schedule.End.bed
    @State private var minute: Int
    @State private var keepsSleep = true
    @State private var stepMinutes = 30
    @State private var everyDays = 1
    @State private var timing = Timing.start
    @State private var date: Date

    init(model: AppModel, done: @escaping () -> Void) {
        self.model = model
        self.done = done
        let today = model.dayLog.day
        guard let shift = model.settings.sleepShift else {
            // An hour earlier, from tonight.
            _minute = State(initialValue: (model.schedule.bedMinute + 23 * 60) % (24 * 60))
            _date = State(initialValue: DayID.date(today) ?? .now)
            return
        }
        // The shift as you set it, from where it's got to.
        let from = model.shiftPosition
        let target = model.settings.schedule
        let bed = SleepShift.distance(from: from.bedMinute, to: target.bedMinute)
        let wake = SleepShift.distance(from: from.wakeMinute, to: target.wakeMinute)
        _end = State(initialValue: shift.leads)
        _minute = State(initialValue: shift.leads == .bed ? target.bedMinute : target.wakeMinute)
        _keepsSleep = State(initialValue: bed == wake)
        _stepMinutes = State(initialValue: shift.stepMinutes)
        _everyDays = State(initialValue: shift.everyDays)
        _timing = State(initialValue: shift.isByFinishDay ? .finish : .start)
        let day = shift.isByFinishDay ? shift.finishDay(target: target) : shift.nextStepDay(from: today)
        _date = State(initialValue: DayID.date(day) ?? .now)
        isChanging = true
    }

    /// Whether this changes the shift under way rather than starting one.
    private var isChanging = false

    var body: some View {
        let from = model.shiftPosition
        let target = from.moving(end, to: minute, keepsSleep: keepsSleep)
        let shift = shift(from: from, target: target, timing: timing)
        let today = model.dayLog.day
        let isLate = (DayID.days(from: today, to: shift.startDay) ?? 0) < 0
        VStack(alignment: .leading, spacing: 10) {
            Picker("Move", selection: $end) {
                Text("Bedtime").tag(Schedule.End.bed)
                Text("Wake time").tag(Schedule.End.wake)
            }
            .pickerStyle(.segmented)
            .onChange(of: end) {
                // An hour earlier than now.
                minute = ((end == .bed ? from.bedMinute : from.wakeMinute) + 23 * 60) % (24 * 60)
            }
            TimeField("To", minute: $minute)
            Toggle(isOn: $keepsSleep) {
                Text(end == .bed ? "Wake time moves too" : "Bedtime moves too")
                let other = end == .bed ? (from.wakeMinute, target.wakeMinute) : (from.bedMinute, target.bedMinute)
                Text(keepsSleep
                    ? "To \(Schedule.clockText(other.1)), so you sleep as long"
                    : "Stays at \(Schedule.clockText(other.0))")
            }
            RowPicker(title: "Step", selection: $stepMinutes, options: [10, 15, 20, 30, 45, 60].map { ("\($0) min", $0) })
            RowPicker(title: "Every", selection: $everyDays, options: (1...7).map { ($0 == 1 ? "day" : "\($0) days", $0) })
            Picker("Set", selection: $timing) {
                Text("Start day").tag(Timing.start)
                Text("Finish day").tag(Timing.finish)
            }
            .pickerStyle(.segmented)
            .onChange(of: timing) { old, new in
                // The same shift, by its other end.
                let shift = self.shift(from: from, target: target, timing: old)
                let day = new == .start ? shift.startDay : shift.finishDay(target: target)
                date = DayID.date(day) ?? date
            }
            ShiftDayPicker(title: timing == .start ? "Starts" : "There by", date: $date, today: today)
            Text(preview(shift, target: target, isLate: isLate))
                .font(.caption)
                .foregroundStyle(isLate ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .monospacedDigit()
            HStack {
                Button("Cancel", action: done)
                Spacer()
                Button(isChanging ? "Save" : "Start Shift") {
                    model.startSleepShift(shift, to: target)
                    done()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(shift.stepCount(to: target) == 0 || isLate)
            }
        }
    }

    /// The shift as set: starting on the chosen day, or starting as late as gets you there by it.
    private func shift(from: Schedule, target: Schedule, timing: Timing) -> SleepShift {
        let day = DayID.string(from: date)
        return switch timing {
        case .start:
            SleepShift(from: from, startDay: day, stepMinutes: stepMinutes, everyDays: everyDays, leads: end)
        case .finish:
            SleepShift(
                from: from, finishingOn: day, target: target, stepMinutes: stepMinutes, everyDays: everyDays,
                leads: end)
        }
    }

    /// "4 steps: 00:30, 00:00, 23:30, 23:00, there on Fri." or, by a day, "… from tonight."
    private func preview(_ shift: SleepShift, target: Schedule, isLate: Bool) -> String {
        let count = shift.stepCount(to: target)
        let today = model.dayLog.day
        guard count > 0 else { return "That's your \(end == .bed ? "bedtime" : "wake time") already." }
        if isLate {
            let soonest = SleepShift(
                from: shift.from, startDay: today, stepMinutes: shift.stepMinutes, everyDays: shift.everyDays)
            let finish = SleepShiftSettings.dayName(soonest.finishDay(target: target), today: today, on: true)
            let steps = "\(count) \(count == 1 ? "step" : "steps")"
            return "\(steps) from tonight gets you there \(finish) at the soonest. Take bigger steps or pick a later day."
        }
        let moved = (1...count).map { step in
            let schedule = shift.schedule(afterSteps: step, target: target)
            return Schedule.clockText(end == .bed ? schedule.bedMinute : schedule.wakeMinute)
        }
        let shown = moved.count > 6 ? moved.prefix(5) + ["…", moved[moved.count - 1]] : moved[...]
        let steps = "\(count) \(count == 1 ? "step" : "steps"): \(shown.joined(separator: ", "))"
        switch timing {
        case .start:
            return "\(steps), there \(SleepShiftSettings.dayName(shift.finishDay(target: target), today: today, on: true))."
        case .finish:
            let start = SleepShiftSettings.dayName(shift.startDay, today: today)
            let night = switch start {
            case "Today": "tonight"
            case "Tomorrow": "tomorrow night"
            default: "\(start) night"
            }
            return "\(steps), from \(night)."
        }
    }
}

/// A day from today on, as the day's own ‹ and › go: a day back or on either side of the date, which picks one from a
/// calendar. ‹ stops at today.
private struct ShiftDayPicker: View {
    let title: String
    @Binding var date: Date
    let today: String
    @State private var showsCalendar = false

    var body: some View {
        let first = DayID.date(today) ?? .now
        LabeledContent(title) {
            HStack(spacing: 2) {
                Button {
                    step(-1)
                } label: {
                    Label("Previous Day", systemImage: "chevron.left")
                }
                .disabled(DayID.string(from: date) <= today)
                .help("Previous Day")
                Button {
                    showsCalendar.toggle()
                } label: {
                    Text(title(of: date)).monospacedDigit()
                }
                .help("Choose a Day")
                .popover(isPresented: $showsCalendar, arrowEdge: .bottom) {
                    DatePicker(title, selection: $date, in: first..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .padding()
                        .presentationCompactAdaptation(.popover)
                }
                Button {
                    step(1)
                } label: {
                    Label("Next Day", systemImage: "chevron.right")
                }
                .help("Next Day")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
    }

    /// "Sat 24 Oct", as the day's own date reads, with the year when it isn't this one.
    private func title(of date: Date) -> String {
        let format = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        let isThisYear = DayID.string(from: date).prefix(4) == today.prefix(4)
        return date.formatted(isThisYear ? format : format.year())
    }

    private func step(_ days: Int) {
        date = DayID.adding(days, to: DayID.string(from: date)).flatMap { DayID.date($0) } ?? date
    }
}
