import AppKit
import SwiftUI
import TimeBlockKit
import TimeBlockUI

/// The current view's whole library, to star activities for the palette or add your own. Starred ones aren't
/// listed apart: the palette shows them, and unstars them too. Editors open in the list rather than a popover:
/// closing a popover hands focus to the first time picker, which scrolls the settings back to the top.
struct ActivitySettings: View {
    @Bindable var model: AppModel
    /// The id of the activity whose editor is open.
    @State private var editing: String?
    @State private var query = ""
    /// Library groups showing their activities.
    @State private var expanded: Set<CategoryGroup> = []

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
                ForEach(CategoryGroup.allCases, id: \.self) { group in
                    let members = all.filter { $0.group == group }
                    let isExpanded = expanded.contains(group)
                    // A plain row rather than a DisclosureGroup, which ignored clicks in this form.
                    Button {
                        if isExpanded { expanded.remove(group) } else { expanded.insert(group) }
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
                            Text("\(members.count)").foregroundStyle(.secondary).monospacedDigit()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if isExpanded {
                        ForEach(members) { category in
                            row(category)
                        }
                    }
                }
            } else {
                ForEach(all) { category in
                    row(category)
                }
            }
            Button("New Activity", systemImage: "plus") {
                let id = model.addActivity(in: track)
                // Show the new activity, with its editor open, wherever it's listed.
                query = ""
                if let group = model.settings.categories.first(where: { $0.id == id })?.group { expanded.insert(group) }
                editing = id
            }
        } header: {
            Text(track == .activity ? "Activities" : "\(track.name) Activities")
        } footer: {
            Text("Starred activities make up the palette, by group; search there finds the rest. Activities in a group share its color, and are summed up together.")
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ category: BlockCategory) -> some View {
        let key = category.id
        let isStarred = model.settings.favorites.contains(category.id)
        let isOwn = model.settings.customCategories.contains { $0.id == category.id }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                let label = HStack {
                    Image(systemName: category.symbol)
                        .foregroundStyle(Color(rgb: category.color))
                        .frame(width: 20)
                    Text(category.name)
                    Spacer()
                }
                .contentShape(Rectangle())
                // Built-in activities have nothing to edit.
                if isOwn {
                    Button {
                        editing = editing == key ? nil : key
                    } label: {
                        label
                    }
                    .buttonStyle(.plain)
                } else {
                    label
                }
                Button {
                    model.toggleFavorite(category.id)
                } label: {
                    Image(systemName: isStarred ? "star.fill" : "star")
                        .foregroundStyle(isStarred ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help(isStarred ? "Unstar" : "Star")
            }
            if isOwn, editing == key {
                ActivityEditor(category: binding(for: category), done: { editing = nil })
            }
        }
    }

    private func binding(for category: BlockCategory) -> Binding<BlockCategory> {
        Binding {
            model.settings.customCategories.first { $0.id == category.id } ?? category
        } set: { edited in
            guard let index = model.settings.customCategories.firstIndex(where: { $0.id == category.id }) else { return }
            model.settings.customCategories[index] = edited
        }
    }
}

/// Edits the name, group and icon of an activity of your own.
private struct ActivityEditor: View {
    @Binding var category: BlockCategory
    let done: () -> Void
    @State private var symbolName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Name", text: $category.name)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
            if category.group != nil {
                Picker("Group", selection: groupBinding) {
                    ForEach(CategoryGroup.allCases, id: \.self) { group in
                        Text(group.name).tag(group)
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

    private var groupBinding: Binding<CategoryGroup> {
        Binding { category.group ?? .life } set: { category.group = $0 }
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
