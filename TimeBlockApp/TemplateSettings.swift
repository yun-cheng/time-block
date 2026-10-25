import SwiftUI
import TimeBlockKit
import TimeBlockUI

/// The routine: time pre-logged on the days it comes back on, such as meals and coffee. Each template picks an
/// activity, a start, a length and its days, and can be paused or removed.
struct TemplateSettings: View {
    @Bindable var model: AppModel
    /// The id of the template whose editor is open.
    @State private var editing: String?

    var body: some View {
        let categories = Dictionary(model.settings.categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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
                            Text(category?.name ?? "Unknown activity")
                            Text("\(Self.times(of: template)) · \(Self.days(template.weekdays))")
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
                    template: binding, activities: activities, groups: model.settings.groups,
                    favorites: model.settings.favorites,
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

    /// "12:00–12:30".
    static func times(of template: Template) -> String {
        "\(clock(template.startMinute))–\(clock(template.startMinute + template.length * Schedule.blockMinutes))"
    }

    private static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60 % 24, minute % 60)
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

/// Edits a template's activity, start, length and days.
private struct TemplateEditor: View {
    @Binding var template: Template
    let activities: [BlockCategory]
    let groups: [CategoryGroup]
    let favorites: [String]
    let remove: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Activity") {
                activityMenu
            }
            TimeField("Starts", minute: $template.startMinute)
            LabeledContent("Length") {
                HStack(spacing: 6) {
                    Text(Self.duration(template.length)).monospacedDigit()
                    // Up to 12 hours.
                    Stepper("Length", value: $template.length, in: 1...(12 * Schedule.blocksPerHour))
                        .labelsHidden()
                }
            }
            LabeledContent("Repeats") {
                HStack(spacing: 3) {
                    ForEach(TemplateSettings.orderedWeekdays(), id: \.self) { weekday in
                        dayButton(weekday)
                    }
                }
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

    /// Starred activities first, then every activity by group.
    private var activityMenu: some View {
        let current = activities.first { $0.id == template.categoryID }
        return Menu {
            Section("Starred") {
                ForEach(activities.filter { favorites.contains($0.id) }) { item($0) }
            }
            ForEach(groups) { group in
                let members = activities.filter { $0.group?.id == group.id }
                if !members.isEmpty {
                    Menu(group.name) {
                        ForEach(members) { item($0) }
                    }
                }
            }
        } label: {
            Label(current?.name ?? "Choose", systemImage: current?.symbol ?? "questionmark")
        }
        .fixedSize()
    }

    private func item(_ category: BlockCategory) -> some View {
        Button {
            template.categoryID = category.id
        } label: {
            Label(category.name, systemImage: category.symbol)
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

    /// "45m", "1h", "1h 30m".
    static func duration(_ blocks: Int) -> String {
        let minutes = blocks * Schedule.blockMinutes
        return switch (minutes / 60, minutes % 60) {
        case (0, let m): "\(m)m"
        case (let h, 0): "\(h)h"
        case (let h, let m): "\(h)h \(m)m"
        }
    }
}
