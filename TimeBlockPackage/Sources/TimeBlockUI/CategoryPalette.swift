#if canImport(AppKit)
import AppKit
#endif
import SwiftUI
import TimeBlockKit

/// What dragging across the grid does.
public enum Brush: Hashable, Sendable {
    /// Logs the category alone, in place of what the blocks held.
    case category(String)
    /// Adds the category to what the blocks hold, or takes it off when they all hold it already.
    case layer(String)
    case clear

    /// The category to log, or nil for clearing.
    public var categoryID: String? {
        switch self {
        case .category(let id), .layer(let id): id
        case .clear: nil
        }
    }
}

/// A category as a tappable chip. Unselected chips are neutral with only the icon in color;
/// the selected one is filled with the category's color and ringed, so it stands out from the rest.
public struct CategoryChip: View {
    let name: String
    let symbol: String
    let color: Color
    /// Text color on the filled chip.
    let filledText: Color
    let theme: MoodTheme
    let isSelected: Bool
    let action: () -> Void

    public init(category: BlockCategory, theme: MoodTheme, isSelected: Bool, action: @escaping () -> Void) {
        name = category.name
        symbol = category.symbol
        color = theme.color(of: category)
        filledText = theme.grade(category.color).luminance > 0.55 ? .black : .white
        self.theme = theme
        self.isSelected = isSelected
        self.action = action
    }

    init(name: String, symbol: String, color: Color, theme: MoodTheme, isSelected: Bool, action: @escaping () -> Void) {
        self.name = name
        self.symbol = symbol
        self.color = color
        filledText = theme.backgroundBottom
        self.theme = theme
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .foregroundStyle(isSelected ? filledText : color)
                Text(name)
                    .foregroundStyle(isSelected ? filledText : theme.secondaryText)
            }
            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(isSelected ? color : theme.text.opacity(0.07)))
            .overlay {
                if isSelected {
                    Capsule().strokeBorder(color, lineWidth: 1.5).padding(-3)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Picks what to log: a search field over every category in the track, the starred ones (then Clear) while it
/// is empty, and the matches while typing. Return takes the best match. Right-clicking a chip stars or unstars it.
/// Clicking a group shows every category in it, starred or not, and narrows search to it; clicking it again goes
/// back. While adding (`isAdding`, or ⌘ held), clicking a chip toggles it rather than choosing it, when there's a way
/// to, and the add pointer over the chips says so.
public struct CategoryPalette: View {
    let categories: [BlockCategory]
    let favorites: [BlockCategory]
    /// The chips lit: what the blocks hold, or the brush.
    let selected: Set<Brush>
    let theme: MoodTheme
    let showsClear: Bool
    let choose: (Brush) -> Void
    /// Adds a category to what's chosen already, or takes it off. Without it a click always chooses.
    let toggle: ((String) -> Void)?
    /// Whether clicks add, as with ⌘ held.
    let isAdding: Bool
    let toggleFavorite: ((String) -> Void)?
    @State private var query = ""
    @State private var groupID: String?
    @State private var isCommandDown = false

    /// `categories` are what search looks through; `favorites` are shown until something is typed.
    public init(
        categories: [BlockCategory], favorites: [BlockCategory], selected: Set<Brush>, theme: MoodTheme,
        showsClear: Bool = true, choose: @escaping (Brush) -> Void, toggle: ((String) -> Void)? = nil,
        isAdding: Bool = false, toggleFavorite: ((String) -> Void)? = nil
    ) {
        self.categories = categories
        self.favorites = favorites
        self.selected = selected
        self.theme = theme
        self.showsClear = showsClear
        self.choose = choose
        self.toggle = toggle
        self.isAdding = isAdding
        self.toggleFavorite = toggleFavorite
    }

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The groups of the track's categories, in their order; none in tracks without groups.
    private var groups: [CategoryGroup] {
        var seen = Set<String>()
        return categories.compactMap(\.group).filter { seen.insert($0.id).inserted }
    }

    /// The group picked, while it still has categories.
    private var group: CategoryGroup? {
        groups.first { $0.id == groupID }
    }

    /// Matches while searching; otherwise the picked group's categories, or the favorites plus the lit categories
    /// that aren't.
    private var shown: [BlockCategory] {
        let group = group
        let pool = group.map { group in categories.filter { $0.group?.id == group.id } } ?? categories
        if isSearching { return Array(ActivitySearch.results(for: query, in: pool).prefix(30)) }
        if group != nil { return pool }
        let lit = Set(selected.compactMap(\.categoryID))
        return favorites + categories.filter { lit.contains($0.id) && !favorites.contains($0) }
    }

    public var body: some View {
        let shown = shown
        VStack(alignment: .leading, spacing: 8) {
            searchField(firstMatch: shown.first)
            let groups = groups
            if groups.count > 1 {
                groupFilter(groups)
            }
            FlowLayout(spacing: 8) {
                ForEach(shown) { category in
                    CategoryChip(
                        category: category, theme: theme,
                        isSelected: selected.contains(.category(category.id)) || selected.contains(.layer(category.id))
                    ) {
                        pick(.category(category.id))
                    }
                    #if canImport(AppKit)
                    .modifier(HoverCursor(cursor: (isAdding || isCommandDown) && toggle != nil ? .dragCopy : nil))
                    #endif
                    .contextMenu {
                        if let toggleFavorite {
                            let isFavorite = favorites.contains { $0.id == category.id }
                            Button(isFavorite ? "Unstar" : "Star", systemImage: isFavorite ? "star.slash" : "star") {
                                toggleFavorite(category.id)
                            }
                        }
                    }
                }
                if showsClear, !isSearching {
                    CategoryChip(name: "Clear", symbol: "eraser", color: theme.text, theme: theme, isSelected: selected.contains(.clear)) {
                        pick(.clear)
                    }
                }
            }
            // Room for the selected chip's ring.
            .padding(3)
            if isSearching, shown.isEmpty {
                Text("Nothing\(group.map { " in \($0.name)" } ?? "") matches \u{201C}\(query)\u{201D}.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .tracksCommandKey($isCommandDown)
    }

    private func searchField(firstMatch: BlockCategory?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.secondaryText)
            TextField("Find an activity", text: $query)
                .textFieldStyle(.plain)
                .foregroundStyle(theme.text)
                .onSubmit {
                    if isSearching, let firstMatch { pick(.category(firstMatch.id)) }
                }
                .onKeyPress(.escape) {
                    if isSearching {
                        query = ""
                    } else if groupID != nil {
                        groupID = nil
                    } else {
                        return .ignored
                    }
                    return .handled
                }
            if isSearching {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .font(.system(size: 12))
        // Room for a long name, not the whole width.
        .frame(maxWidth: 200)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(theme.text.opacity(0.07)))
    }

    /// Tabs over the chips, Starred then a tab per group: plain words, underlined when picked, so they read as
    /// views of the list rather than more chips to log with.
    private func groupFilter(_ groups: [CategoryGroup]) -> some View {
        FlowLayout(spacing: 12) {
            groupTab("Starred", color: theme.text, isPicked: groupID == nil, help: "Show starred activities") {
                groupID = nil
            }
            ForEach(groups) { group in
                let isPicked = group.id == groupID
                groupTab(
                    group.name, color: Color(rgb: theme.grade(group.color)), isPicked: isPicked,
                    help: isPicked ? "Show starred activities" : "Show all of \(group.name)"
                ) {
                    groupID = isPicked ? nil : group.id
                }
            }
        }
    }

    private func groupTab(
        _ name: String, color: Color, isPicked: Bool, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(name.uppercased())
                .font(.system(size: 9.5, weight: isPicked ? .bold : .semibold))
                .tracking(0.6)
                .foregroundStyle(isPicked ? theme.text : theme.secondaryText.opacity(0.8))
                .lineLimit(1)
                .padding(.bottom, 4)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(color)
                        .frame(height: 2)
                        .opacity(isPicked ? 1 : 0)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    private func pick(_ choice: Brush) {
        query = ""
        if let toggle, let id = choice.categoryID, isAdding || Self.isCommandDown {
            toggle(id)
        } else {
            choose(choice)
        }
    }

    private static var isCommandDown: Bool {
        #if canImport(AppKit)
        NSEvent.modifierFlags.contains(.command)
        #else
        false
        #endif
    }
}

/// Lays views out left to right, wrapping onto new lines.
public struct FlowLayout: Layout {
    var spacing: CGFloat

    public init(spacing: CGFloat = 6) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = frames(for: subviews, width: proposal.width ?? .infinity)
        let width = frames.map(\.maxX).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: frames.map(\.maxY).max() ?? 0)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(for: subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .unspecified)
        }
    }

    private func frames(for subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var point = CGPoint.zero
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if point.x > 0, point.x + size.width > width {
                point = CGPoint(x: 0, y: point.y + lineHeight + spacing)
                lineHeight = 0
            }
            frames.append(CGRect(origin: point, size: size))
            point.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return frames
    }
}
