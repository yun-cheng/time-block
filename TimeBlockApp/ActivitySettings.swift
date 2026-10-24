import AppKit
import SwiftUI
import TimeBlockKit
import TimeBlockUI

/// The current view's activities: the starred ones the palette shows, in order, and the whole library to
/// star more from or add your own to. Editors open in the list rather than a popover: closing a popover
/// hands focus to the first time picker, which scrolls the settings back to the top.
struct ActivitySettings: View {
    @Bindable var model: AppModel
    /// The row whose editor is open, as "starred:<id>" or "all:<id>", since one activity can be in both lists.
    @State private var editing: String?
    @State private var query = ""
    /// Library groups showing their activities.
    @State private var expanded: Set<CategoryGroup> = []

    var body: some View {
        let track = model.settings.track
        let all = model.settings.categories.filter { $0.track == track && !$0.isRetired }
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let starred = model.settings.favorites.compactMap { byID[$0] }
        Section {
            ForEach(starred) { category in
                row(category, list: "starred")
            }
            Button("New Activity", systemImage: "plus") {
                editing = "starred:" + model.addActivity(in: track)
            }
        } header: {
            Text(track == .activity ? "Starred" : "Starred \(track.name) Activities")
        } footer: {
            Text("The palette shows these, in this order. Search there finds every other activity.")
                .foregroundStyle(.secondary)
        }
        Section {
            TextField("Search", text: $query, prompt: Text("Search \(all.count) activities"))
                .labelsHidden()
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                ForEach(ActivitySearch.results(for: query, in: all)) { category in
                    row(category, list: "all")
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
                            row(category, list: "all")
                        }
                    }
                }
            } else {
                ForEach(all) { category in
                    row(category, list: "all")
                }
            }
        } header: {
            Text(track == .activity ? "All Activities" : "All \(track.name) Activities")
        } footer: {
            Text("Activities in a group share its color, and are summed up together.")
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ category: BlockCategory, list: String) -> some View {
        let key = "\(list):\(category.id)"
        let isStarred = model.settings.favorites.contains(category.id)
        let isOwn = model.settings.customCategories.contains { $0.id == category.id }
        // Built-in activities have nothing to edit outside the starred list, where they can be moved.
        let isEditable = isOwn || list == "starred"
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
                if isEditable {
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
            if editing == key {
                ActivityEditor(
                    category: binding(for: category), isOwn: isOwn,
                    move: list == "starred" ? { model.moveFavorite(category.id, by: $0) } : nil,
                    done: { editing = nil })
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

/// Moves a starred activity, and edits the name, group and icon of one of your own.
private struct ActivityEditor: View {
    @Binding var category: BlockCategory
    let isOwn: Bool
    /// Moves the activity up (-1) or down (+1) in the palette; nil outside the starred list.
    let move: ((Int) -> Void)?
    let done: () -> Void
    @State private var symbolName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isOwn {
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
            }
            HStack {
                if let move {
                    Button("Move Up", systemImage: "arrow.up") { move(-1) }
                        .help("Move Up")
                    Button("Move Down", systemImage: "arrow.down") { move(1) }
                        .help("Move Down")
                }
                Spacer()
                Button("Done", action: done)
            }
        }
        .labelStyle(.iconOnly)
        .padding(.leading, 28)
        .padding(.bottom, 4)
        .onDisappear {
            if isOwn, category.name.trimmingCharacters(in: .whitespaces).isEmpty { category.name = "Untitled" }
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
