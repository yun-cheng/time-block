import AppKit
import SwiftUI
import TimeBlockKit
import TimeBlockUI

/// The current view's whole library: star activities for the palette, edit any activity or group (built-in ones
/// too, with a way back), or add your own. Starred ones aren't listed apart: the palette shows them, and unstars
/// them too. Editors open in the list rather than a popover: closing a popover hands focus to the first time
/// picker, which scrolls the settings back to the top.
struct ActivitySettings: View {
    @Bindable var model: AppModel
    /// The id of the activity whose editor is open.
    @State private var editing: String?
    /// The id of the group whose editor is open, apart from activities' since Work is both.
    @State private var editingGroup: String?
    @State private var query = ""
    /// Ids of the groups showing their activities.
    @State private var expanded: Set<String> = []

    var body: some View {
        let track = model.settings.track
        let all = model.settings.categories.filter { $0.track == track && !$0.isRetired }
        Section {
            TextField("Search", text: $query, prompt: Text("Search \(all.count) activities"))
                .labelsHidden()
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                ForEach(ActivitySearch.results(for: query, in: all)) { category in
                    row(category)
                }
            } else if track == .activity {
                ForEach(model.settings.groups) { group in
                    let members = all.filter { $0.group?.id == group.id }
                    groupRow(group, count: members.count)
                    if editingGroup == group.id {
                        GroupEditor(
                            group: groupBinding(for: group), isEdited: model.settings.isEdited(group.id),
                            canRemove: !group.isBuiltIn && members.isEmpty,
                            reset: { model.settings.reset(group.id) },
                            remove: { model.removeGroup(group.id) },
                            done: { editingGroup = nil })
                    }
                    if expanded.contains(group.id) {
                        ForEach(members) { category in
                            row(category, indented: true)
                        }
                        Button("New Activity", systemImage: "plus") {
                            editing = model.addActivity(in: track, group: group)
                        }
                        .buttonStyle(.borderless)
                        .padding(.leading, Self.indent)
                    }
                }
                Button("New Group", systemImage: "folder.badge.plus") {
                    let id = model.addGroup()
                    expanded.insert(id)
                    editingGroup = id
                }
            } else {
                ForEach(all) { category in
                    row(category)
                }
                Button("New Activity", systemImage: "plus") {
                    editing = model.addActivity(in: track)
                }
            }
        } header: {
            Text(track == .activity ? "Activities" : "\(track.name) Activities")
        } footer: {
            Text("Starred activities make up the palette, by group; search there finds the rest. Activities in a group share its color, and are summed up together.")
                .foregroundStyle(.secondary)
        }
    }

    /// How far a group's activities sit in from it.
    private static let indent: CGFloat = 22

    private func groupRow(_ group: CategoryGroup, count: Int) -> some View {
        let isExpanded = expanded.contains(group.id)
        return HStack {
            // A plain row rather than a DisclosureGroup, which ignored clicks in this form.
            Button {
                if isExpanded { expanded.remove(group.id) } else { expanded.insert(group.id) }
            } label: {
                HStack {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Circle().fill(Color(rgb: group.color)).frame(width: 10, height: 10)
                    Text(group.name)
                    Spacer()
                    Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                editingGroup = editingGroup == group.id ? nil : group.id
            } label: {
                Image(systemName: "pencil").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Edit Group")
        }
    }

    private func row(_ category: BlockCategory, indented: Bool = false) -> some View {
        let isStarred = model.settings.favorites.contains(category.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    editing = editing == category.id ? nil : category.id
                } label: {
                    HStack {
                        Image(systemName: category.symbol)
                            .foregroundStyle(Color(rgb: category.color))
                            .frame(width: 20)
                        Text(category.name)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    model.toggleFavorite(category.id)
                } label: {
                    Image(systemName: isStarred ? "star.fill" : "star")
                        .foregroundStyle(isStarred ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help(isStarred ? "Unstar" : "Star")
            }
            if editing == category.id {
                ActivityEditor(
                    category: binding(for: category), groups: model.settings.groups,
                    isEdited: model.settings.isEdited(category.id),
                    reset: { model.settings.reset(category.id) }, done: { editing = nil })
            }
        }
        .padding(.leading, indented ? Self.indent : 0)
    }

    private func groupBinding(for group: CategoryGroup) -> Binding<CategoryGroup> {
        Binding {
            model.settings.groups.first { $0.id == group.id } ?? group
        } set: {
            model.settings.save($0)
        }
    }

    private func binding(for category: BlockCategory) -> Binding<BlockCategory> {
        // Read through `categories`, which has your edits and the activity's group as it is now.
        Binding {
            model.settings.categories.first { $0.id == category.id } ?? category
        } set: {
            model.settings.save($0)
        }
    }
}

/// Renames and recolors a group. A built-in one can go back to how it came; one of your own can be removed once
/// it's empty.
private struct GroupEditor: View {
    @Binding var group: CategoryGroup
    let isEdited: Bool
    let canRemove: Bool
    let reset: () -> Void
    let remove: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Group name", text: $group.name)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                ColorPicker("Color", selection: color, supportsOpacity: false)
                    .labelsHidden()
            }
            HStack {
                if canRemove {
                    Button("Remove Group", role: .destructive, action: remove)
                }
                if isEdited {
                    Button("Reset", action: reset)
                        .help("Put back the built-in name and color")
                }
                Spacer()
                Button("Done", action: done)
            }
        }
        .padding(.leading, 28)
        .padding(.bottom, 4)
        .onDisappear {
            if group.name.trimmingCharacters(in: .whitespaces).isEmpty { group.name = "Untitled" }
        }
    }

    private var color: Binding<Color> {
        Binding {
            Color(rgb: group.color)
        } set: { color in
            guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            group.color = RGB(r: srgb.redComponent, g: srgb.greenComponent, b: srgb.blueComponent)
        }
    }
}

/// Edits the name, group and icon of an activity (the color, for a posture). A built-in one can go back to how
/// it came.
private struct ActivityEditor: View {
    @Binding var category: BlockCategory
    let groups: [CategoryGroup]
    let isEdited: Bool
    let reset: () -> Void
    let done: () -> Void
    @State private var symbolName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Name", text: $category.name)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
            if category.group != nil {
                Picker("Group", selection: groupBinding) {
                    ForEach(groups) { group in
                        Text(group.name).tag(group.id)
                    }
                }
            } else {
                ColorPicker("Color", selection: colorBinding, supportsOpacity: false)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 26, maximum: 30), spacing: 2)], spacing: 2) {
                ForEach(Self.symbols, id: \.self) { symbol in
                    symbolButton(symbol)
                }
            }
            TextField("Other SF Symbol name", text: $symbolName)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .onSubmit {
                    let name = symbolName.trimmingCharacters(in: .whitespaces)
                    if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
                        category.symbol = name
                        symbolName = ""
                    }
                }
            HStack {
                if isEdited {
                    Button("Reset", action: reset)
                        .help("Put back the built-in name, group and icon")
                }
                Spacer()
                Button("Done", action: done)
            }
        }
        .padding(.leading, 28)
        .padding(.bottom, 4)
        .onDisappear {
            if category.name.trimmingCharacters(in: .whitespaces).isEmpty { category.name = "Untitled" }
        }
    }

    private var groupBinding: Binding<String> {
        Binding {
            category.group?.id ?? CategoryGroup.life.id
        } set: { id in
            category.group = groups.first { $0.id == id }
        }
    }

    private var colorBinding: Binding<Color> {
        Binding {
            Color(rgb: category.color)
        } set: { color in
            guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            category.color = RGB(r: srgb.redComponent, g: srgb.greenComponent, b: srgb.blueComponent)
        }
    }

    private func symbolButton(_ symbol: String) -> some View {
        let isSelected = symbol == category.symbol
        return Button {
            category.symbol = symbol
        } label: {
            Image(systemName: symbol)
                .frame(width: 26, height: 22)
                .foregroundStyle(isSelected ? Color.white : Color(rgb: category.color))
                .background(RoundedRectangle(cornerRadius: 5).fill(isSelected ? Color(rgb: category.color) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(symbol)
    }

    /// Every icon the built-in activities use, once each.
    private static let symbols: [String] = {
        var seen = Set<String>()
        return BlockCategory.defaults.map(\.symbol).filter { seen.insert($0).inserted }
    }()
}
