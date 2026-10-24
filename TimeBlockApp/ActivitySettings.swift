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
    /// The id of the group showing its activities: one at a time.
    @State private var expanded: String?

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
                    if expanded == group.id {
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
                    expanded = id
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
        // An activity moved to another group takes its open editor along: show that group (the editor scrolls
        // itself into view there).
        .onChange(of: editing.flatMap { id in all.first { $0.id == id }?.group?.id }) { old, new in
            if let new, old != nil { expanded = new }
        }
    }

    /// How far a group's activities sit in from it.
    private static let indent: CGFloat = 22

    private func groupRow(_ group: CategoryGroup, count: Int) -> some View {
        let isExpanded = expanded == group.id
        return HStack {
            // A plain row rather than a DisclosureGroup, which ignored clicks in this form.
            Button {
                expanded = isExpanded ? nil : group.id
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
        .background {
            // Opening it closes the one open before, which may pull it up out of sight.
            if isExpanded { ScrollIntoView() }
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
        .background {
            if editing == category.id { ScrollIntoView() }
        }
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

/// Scrolls the settings to show what it's behind once it's in a window: a group just opened, or a row whose editor
/// opened near the bottom or moved along with its activity to another group. (`ScrollViewReader` doesn't reach
/// into a `Form`'s rows.)
private struct ScrollIntoView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            // Once the rows have laid out around it.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // Clear of the toolbar, which the settings scroll under, with room to spare at either end.
                let toolbar = self.window?.contentView?.safeAreaInsets.top ?? 0
                NSAnimationContext.runAnimationGroup { _ in
                    self.scrollToVisible(self.bounds.insetBy(dx: 0, dy: -(toolbar + 8)))
                }
            }
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
    @State private var picksIcon = false
    @FocusState private var focusesName: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    picksIcon.toggle()
                } label: {
                    Image(systemName: category.symbol)
                        .foregroundStyle(Color(rgb: category.color))
                        .frame(width: 22, height: 18)
                }
                .help("Choose Icon")
                .popover(isPresented: $picksIcon, arrowEdge: .bottom) {
                    IconPicker(selected: category.symbol, color: Color(rgb: category.color)) { symbol in
                        category.symbol = symbol
                        picksIcon = false
                    }
                }
                .onChange(of: picksIcon) { _, isOpen in
                    // Closing a popover hands focus to the first time picker, scrolling the settings to the top;
                    // keep it here instead.
                    if !isOpen { focusesName = true }
                }
                TextField("Name", text: $category.name)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .focused($focusesName)
            }
            if category.group != nil {
                Picker("Group", selection: groupBinding) {
                    ForEach(groups) { group in
                        Text(group.name).tag(group.id)
                    }
                }
            } else {
                ColorPicker("Color", selection: colorBinding, supportsOpacity: false)
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
}

/// The icons the built-in activities use, searchable by the icon's own name ("fork.knife") or by the activities
/// that use it ("lunch", "meal"). Any other SF Symbol can be typed by its exact name.
private struct IconPicker: View {
    let selected: String
    let color: Color
    let choose: (String) -> Void
    @State private var query = ""

    var body: some View {
        let icons = Self.results(for: query)
        VStack(alignment: .leading, spacing: 10) {
            // Laid out like the palette's search, so the clear button sits beside the text rather than over it.
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search icons", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { if let first = icons.first { choose(first) } }
                    // Escape clears a search first, then closes the popover.
                    .onKeyPress(.escape) {
                        guard !query.isEmpty else { return .ignored }
                        query = ""
                        return .handled
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(.primary.opacity(0.07)))
            .padding(.horizontal, Self.margin)
            // AppKit's scroll bar would run out past the popover's bubble; this one stays in the margin.
            AppScrollView(lane: Self.margin) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.cell), spacing: Self.gap), count: Self.columns),
                          spacing: Self.gap) {
                    ForEach(icons, id: \.self) { symbol in
                        iconButton(symbol)
                    }
                }
                .padding(.horizontal, Self.margin)
                .padding(.bottom, Self.margin)
            }
            .frame(width: Self.width, height: Self.height)
            .overlay {
                if icons.isEmpty {
                    Text("No icon named “\(query)”").foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, Self.margin)
        .frame(width: Self.width)
    }

    private static let height: CGFloat = 240
    private static let margin: CGFloat = 14
    private static let width = CGFloat(columns) * (cell + gap) - gap + 2 * margin

    private static let columns = 9
    private static let cell: CGFloat = 30
    private static let gap: CGFloat = 4

    private func iconButton(_ symbol: String) -> some View {
        let isSelected = symbol == selected
        return Button {
            choose(symbol)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: Self.cell, height: 26)
                .foregroundStyle(isSelected ? Color.white : color)
                .background(RoundedRectangle(cornerRadius: 5).fill(isSelected ? color : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(symbol)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Each icon once, with the words it can be found by.
    private static let catalog: [(symbol: String, words: [String])] = {
        var order: [String] = []
        var words: [String: Set<String>] = [:]
        for category in BlockCategory.defaults {
            if words[category.symbol] == nil { order.append(category.symbol) }
            let terms = [category.symbol, category.name] + category.keywords
            let split = terms.flatMap { fold($0).split { !$0.isLetter && !$0.isNumber }.map(String.init) }
            words[category.symbol, default: []].formUnion(split)
        }
        return order.map { ($0, Array(words[$0] ?? [])) }
    }()

    /// Icons with a word starting with every word of `query`, plus the SF Symbol named exactly `query`.
    static func results(for query: String) -> [String] {
        let query = fold(query).trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return catalog.map(\.symbol) }
        let tokens = query.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        var found = catalog.filter { icon in
            tokens.allSatisfy { token in icon.words.contains { $0.hasPrefix(token) } }
        }.map(\.symbol)
        if !found.contains(query), NSImage(systemSymbolName: query, accessibilityDescription: nil) != nil {
            found.insert(query, at: 0)
        }
        return found
    }
}
