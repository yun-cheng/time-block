import SwiftUI
import TimeBlockUI

/// A dialog in the middle of the window's day, which dims behind it; a click there closes it. It fits in the window:
/// as wide as `width` where there's room, and no taller than the window, so what's in it should scroll when it's
/// longer.
struct Dialog<Content: View>: View {
    var width: CGFloat
    var fill: Color
    /// How much lighter than `fill` it's drawn, raised off a day of the same color, as dark mode raises its sheets.
    var lift = 0.0
    var stroke: Color
    @Binding var isOpen: Bool
    @ViewBuilder let content: Content

    /// The least room left around it, to the window's edges: the day's own, so it lines up with the day's column.
    private static var margin: CGFloat { 32 }

    var body: some View {
        ZStack {
            // Dark enough to set the dialog off a dark day as well as a light one.
            Color.black.opacity(0.5)
                .contentShape(Rectangle())
                .onTapGesture { isOpen = false }
            // What scrolls fills the room it has; the rest keeps its own height.
            content
                .frame(maxWidth: width)
                .background {
                    RoundedRectangle(cornerRadius: 14).fill(fill)
                    RoundedRectangle(cornerRadius: 14).fill(.white.opacity(lift))
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(stroke))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
                .padding(Self.margin)
        }
    }
}
