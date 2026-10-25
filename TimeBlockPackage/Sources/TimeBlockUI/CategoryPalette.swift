import SwiftUI
import TimeBlockKit

/// What dragging across the grid does.
public enum Brush: Hashable, Sendable {
    case category(String)
    case clear

    /// The category to log, or nil for clearing.
    public var categoryID: String? {
        if case .category(let id) = self { id } else { nil }
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
/// back.
public struct CategoryPalette: View {
    let categories: [BlockCategory]
    let favorites: [BlockCategory]
    let selected: Brush?
    let theme: MoodTheme
    let showsClear: Bool
    let choose: (Brush) -> Void
    let toggleFavorite: ((String) -> Void)?
    @State private var query = ""
    @State private var groupID: String?

    /// `categories` are what search looks through; `favorites` are shown until something is typed.
    public init(
        categories: [BlockCategory], favorites: [BlockCategory], selected: Brush?, theme: MoodTheme,
        showsClear: Bool = true, choose: @escaping (Brush) -> Void, toggleFavorite: ((String) -> Void)? = nil
    ) {
        self.categories = categories
        self.favorites = favorites
        self.selected = selected
        self.theme = theme
        self.showsClear = showsClear
        self.choose = choose
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

    /// Matches while searching; otherwise the picked group's categories, or the favorites plus the picked category
    /// when it isn't one.
    private var shown: [BlockCategory] {
        let group = group
        let pool = group.map { group in categories.filter { $0.group?.id == group.id } } ?? categories
        if isSearching { return Array(ActivitySearch.results(for: query, in: pool).prefix(30)) }
        if group != nil { return pool }
        guard let id = selected?.categoryID, !favorites.contains(where: { $0.id == id }),
              let picked = categories.first(where: { $0.id == id })
        else { return favorites }
        return favorites + [picked]
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
                    CategoryChip(category: category, theme: theme, isSelected: selected == .category(category.id)) {
                        pick(.category(category.id))
                    }
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
                    CategoryChip(name: "Clear", symbol: "eraser", color: theme.text, theme: theme, isSelected: selected == .clear) {
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
        choose(choice)
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
