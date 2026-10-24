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

/// This track's categories, then Clear. `selected` is drawn as picked; clicks go to `choose`.
public struct CategoryPalette: View {
    let categories: [BlockCategory]
    let selected: Brush?
    let theme: MoodTheme
    let choose: (Brush) -> Void

    public init(categories: [BlockCategory], selected: Brush?, theme: MoodTheme, choose: @escaping (Brush) -> Void) {
        self.categories = categories
        self.selected = selected
        self.theme = theme
        self.choose = choose
    }

    public var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(categories) { category in
                CategoryChip(category: category, theme: theme, isSelected: selected == .category(category.id)) {
                    choose(.category(category.id))
                }
            }
            CategoryChip(name: "Clear", symbol: "eraser", color: theme.text, theme: theme, isSelected: selected == .clear) {
                choose(.clear)
            }
        }
        // Room for the selected chip's ring.
        .padding(3)
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
