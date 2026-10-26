import SwiftUI
import TimeBlockKit

/// What clicking an activity does, picked like a tool in a photo editor and shown by the pointer: the usual arrow, or
/// the add pointer (an arrow with a green plus) while adding. Holding ⌘ adds as well, for as long as it's held.
public enum Tool: String, CaseIterable, Hashable, Sendable {
    /// An activity replaces what the blocks hold.
    case normal
    /// An activity is added to what the blocks hold, or comes off where they all hold it.
    case add

    public var name: String {
        switch self {
        case .normal: "Normal"
        case .add: "Add"
        }
    }

    var help: String {
        switch self {
        case .normal: "Normal: an activity replaces what blocks hold"
        case .add: "Add: an activity is added to what blocks hold, or comes off (or hold ⌘)"
        }
    }
}

/// The tools side by side, the one picked filled in, each drawn as the pointer it gives.
struct ToolPicker: View {
    let tool: Tool
    let theme: MoodTheme
    let pick: (Tool) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Tool.allCases, id: \.self) { option in
                let isPicked = option == tool
                Button {
                    pick(option)
                } label: {
                    icon(option)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isPicked ? theme.backgroundBottom : theme.secondaryText)
                        .frame(width: 30, height: 22)
                        .background(RoundedRectangle(cornerRadius: 5).fill(isPicked ? theme.text : .clear))
                        .contentShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help(option.help)
                .accessibilityLabel(option.name)
                .accessibilityAddTraits(isPicked ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(theme.text.opacity(0.07)))
    }

    @ViewBuilder private func icon(_ tool: Tool) -> some View {
        switch tool {
        case .normal: Image(systemName: "cursorarrow")
        case .add:
            Image(systemName: "cursorarrow")
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 8, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .green)
                        .offset(x: 5, y: 3)
                }
        }
    }
}
