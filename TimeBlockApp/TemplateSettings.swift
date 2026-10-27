import SwiftUI
import TimeBlockKit
import TimeBlockUI

/// The routine: time pre-logged on the days it comes back on, such as meals and coffee. Each template picks an
/// activity, a start, a length and its days, can notify when it starts, and can be paused or removed.
struct TemplateSettings: View {
    @Bindable var model: AppModel
    /// The id of the template whose editor is open.
    @State private var editing: String?

    var body: some View {
        Section {
            ForEach(model.settings.templates) { template in
                row(template, category: categories[template.categoryID])
            }
            Button("Add to Routine", systemImage: "plus") {
                editing = model.addTemplate()
            }
        } header: {
            Text("Routine")
        }
    }

    private func row(_ template: Template, category: BlockCategory?) -> some View {
        let binding = binding(for: template)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    editing = editing == template.id ? nil : template.id
                } label: {
                    HStack {
                        Image(systemName: category?.symbol ?? "questionmark")
                            .foregroundStyle(category.map { Color(rgb: $0.color) } ?? .secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(category?.name ?? "Unknown activity")
                                if template.notifies {
                                    Image(systemName: "bell.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .help("Notifies when it starts")
                                }
                            }
                            Text(Self.subtitle(
                                of: template, categories: categories, today: model.dayLog, schedule: model.schedule))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Spacer()
                    }
                    .opacity(template.isEnabled ? 1 : 0.5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Toggle("On", isOn: binding.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .help(template.isEnabled ? "Pause" : "Resume")
            }
            if editing == template.id {
                TemplateEditor(
                    template: binding, activities: activities, favorites: model.settings.favorites,
                    today: model.dayLog, schedule: model.schedule,
                    remove: {
                        editing = nil
                        model.settings.templates.removeAll { $0.id == template.id }
                    },
                    done: { editing = nil })
            }
        }
        .background {
            if editing == template.id { ScrollIntoView() }
        }
    }

    private var categories: [String: BlockCategory] {
        Dictionary(model.settings.categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var activities: [BlockCategory] {
        model.settings.categories.filter { $0.track == .activity && !$0.isRetired }
    }

    private func binding(for template: Template) -> Binding<Template> {
        Binding {
            model.settings.templates.first { $0.id == template.id } ?? template
        } set: { changed in
            guard let index = model.settings.templates.firstIndex(where: { $0.id == changed.id }) else { return }
            model.settings.templates[index] = changed
        }
    }

    /// "12:00–12:30 · Weekdays", "07:30–08:00 · 30m after waking · Every day", or "10:15–10:30, 18:15–18:30 · 15m
    /// after Gym · Weekdays", with `today`'s times: each time after an activity, and none when it isn't on today.
    static func subtitle(
        of template: Template, categories: [String: BlockCategory], today: DayLog, schedule: Schedule
    ) -> String {
        let starts = template.anchor == .after
            ? today.ends(of: template).map { template.startMinute(in: schedule, following: $0) }
            : [template.startMinute(in: schedule)]
        let times = starts.isEmpty ? nil : starts.map {
            "\(Schedule.clockText($0))–\(Schedule.clockText($0 + template.length * Schedule.blockMinutes))"
        }.joined(separator: ", ")
        let offset = durationText(minutes: template.offset)
        let anchor: String? = switch template.anchor {
        case .clock: nil
        case .wake: "\(offset) after waking"
        case .bed: "\(offset) before bed"
        case .after:
            [template.offset == 0 ? nil : offset, "after",
             template.afterCategoryID.flatMap { categories[$0]?.name } ?? "an activity"]
                .compactMap { $0 }.joined(separator: " ")
        }
        return [times, anchor, days(template.weekdays)].compactMap { $0 }.joined(separator: " · ")
    }

    /// "Every day", "Weekdays", "Weekends", "Every day but Sun", or the days themselves: "Mon, Wed, Fri".
    static func days(_ weekdays: Set<Int>, calendar: Calendar = .current) -> String {
        switch weekdays {
        case Template.everyDay: "Every day"
        case Template.weekdaysOnly: "Weekdays"
        case Template.weekends: "Weekends"
        case []: "Never"
        case _ where weekdays.count == 6:
            "Every day but \(Template.everyDay.subtracting(weekdays).map { calendar.shortWeekdaySymbols[$0 - 1] }[0])"
        default:
            orderedWeekdays(calendar).filter(weekdays.contains)
                .map { calendar.shortWeekdaySymbols[$0 - 1] }
                .joined(separator: ", ")
        }
    }

    /// The days of the week in the order the calendar shows them, starting on its first weekday.
    static func orderedWeekdays(_ calendar: Calendar = .current) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }
}

/// Edits a template's activity, start, length, days and whether it notifies.
private struct TemplateEditor: View {
    @Binding var template: Template
    let activities: [BlockCategory]
    let favorites: [String]
    /// Today's logs and schedule: going back to a clock time starts it where it starts today.
    let today: DayLog
    let schedule: Schedule
    let remove: () -> Void
    let done: () -> Void
    @State private var showsActivities = false
    @State private var showsFollowed = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Activity") {
                activityButton(template.categoryID, help: "Choose the activity", isPresented: $showsActivities) {
                    template.categoryID = $0
                }
            }
            // What it's counted from, and under it the time, so the time stays put whichever it is.
            LabeledContent("Starts") {
                VStack(alignment: .trailing, spacing: 6) {
                    anchorPicker
                    if template.anchor == .after {
                        activityButton(
                            template.afterCategoryID, help: "Choose the activity it starts after",
                            isPresented: $showsFollowed
                        ) {
                            template.anchor(to: .after, after: $0, in: schedule)
                        }
                    }
                    startField
                }
            }
            LabeledContent("Length") {
                // A block to 12 hours.
                DurationPicker(
                    title: "Length",
                    minutes: Binding { template.length * Schedule.blockMinutes } set: {
                        template.length = $0 / Schedule.blockMinutes
                    },
                    range: Schedule.blockMinutes...(12 * 60))
            }
            LabeledContent("Repeats") {
                HStack(spacing: 3) {
                    ForEach(TemplateSettings.orderedWeekdays(), id: \.self) { weekday in
                        dayButton(weekday)
                    }
                }
            }
            LabeledContent("Notify") {
                Toggle("Notify", isOn: $template.notifies)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .help("Notify when it starts, each time, where it's still pre-logged")
            }
            HStack {
                Button("Remove", role: .destructive, action: remove)
                    .help("Take it out of the routine, and the blocks it pre-logged that are still to come")
                Spacer()
                Button("Done", action: done)
            }
        }
        .padding(.leading, 28)
        .padding(.bottom, 4)
    }

    /// An activity, or a prompt to choose one; a click opens the activities, as the timer's does.
    private func activityButton(
        _ id: String?, help: String, isPresented: Binding<Bool>, choose: @escaping (String) -> Void
    ) -> some View {
        let current = activities.first { $0.id == id }
        return Button {
            isPresented.wrappedValue = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: current?.symbol ?? "tag")
                    .foregroundStyle(current.map { Color(rgb: $0.color) } ?? .secondary)
                Text(current?.name ?? "Choose Activity")
                    .foregroundStyle(current == nil ? .secondary : .primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(0.07)))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(help)
        .popover(isPresented: isPresented, arrowEdge: .bottom) {
            CategoryPalette(
                categories: activities, favorites: activities.filter { favorites.contains($0.id) },
                selected: id.map { [.category($0)] } ?? [],
                // Drawn like the settings around it, whatever the day's mood.
                theme: MoodTheme(mood: .calm, colorScheme: colorScheme), showsClear: false,
                choose: { choice in
                    if let id = choice.categoryID { choose(id) }
                    isPresented.wrappedValue = false
                })
            .padding(14)
            .palettePopover()
        }
    }

    private func dayButton(_ weekday: Int) -> some View {
        let isOn = template.weekdays.contains(weekday)
        let calendar = Calendar.current
        return Button {
            if isOn { template.weekdays.remove(weekday) } else { template.weekdays.insert(weekday) }
        } label: {
            Text(calendar.veryShortWeekdaySymbols[weekday - 1])
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 20, height: 20)
                .foregroundStyle(isOn ? Color.white : Color.secondary)
                .background(Circle().fill(isOn ? Color.accentColor : Color.primary.opacity(0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(calendar.weekdaySymbols[weekday - 1])
    }

    /// What it starts from: a clock time, waking, bed, or the end of an activity, picked under it.
    private var anchorPicker: some View {
        RowPicker(
            title: "Starts", selection: anchorBinding,
            options: [("At", .clock), ("After Waking", .wake), ("Before Bed", .bed), ("After Activity", .after)])
            .labelsHidden()
        .fixedSize()
    }

    /// The clock time it starts at, or how long after waking, before bed, or after the activity it follows.
    @ViewBuilder private var startField: some View {
        if template.anchor == .clock {
            TimeField("Starts", minute: $template.startMinute)
                .labelsHidden()
        } else {
            // Up to a whole day.
            DurationPicker(title: "Starts", minutes: $template.offset, range: 0...(24 * 60 - Schedule.blockMinutes))
        }
    }

    private var anchorBinding: Binding<Template.Anchor> {
        Binding { template.anchor } set: {
            template.anchor(
                to: $0, after: template.afterCategoryID, in: schedule, following: today.ends(of: template).first)
        }
    }

}
