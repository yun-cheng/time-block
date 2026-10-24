import SwiftUI
import TimeBlockKit

/// The big "blocks left" number, with the day's usable total beside it.
/// Past bedtime it turns red, then splits into a glitch.
public struct CounterView: View {
    let value: Int
    let theme: MoodTheme
    let size: CGFloat
    /// Usable blocks in the day, shown as "/192"; nil hides it.
    var total: Int?
    var time: Double

    public init(value: Int, theme: MoodTheme, size: CGFloat, total: Int? = nil, time: Double = 0) {
        self.value = value
        self.theme = theme
        self.size = size
        self.total = total
        self.time = time
    }

    private var label: String { value < 0 ? "\u{2212}\(-value)" : "\(value)" }

    public var body: some View {
        let mood = theme.mood
        let glitch = mood >= .dread
        let flutter = time > 0 ? 0.6 + 0.4 * sin(time * 23) : 1
        let split = glitch ? size * (mood == .nightmare ? 0.05 : 0.03) * flutter : 0
        let shake = time > 0 && mood == .nightmare ? sin(time * 53) * size * 0.02 : 0
        let horror = mood >= .uneasy

        HStack(alignment: .firstTextBaseline, spacing: size * 0.04) {
            ZStack {
                if glitch {
                    Text(label).foregroundStyle(Color(hex: 0xFF0033, opacity: 0.75)).offset(x: -split, y: split * 0.3)
                    Text(label).foregroundStyle(Color(hex: 0x00E5FF, opacity: 0.45)).offset(x: split, y: -split * 0.3)
                }
                Text(label).foregroundStyle(mood == .calm ? theme.text : theme.accent)
            }
            .font(horror
                ? .system(size: size, weight: .black, design: .monospaced)
                : .system(size: size, weight: .bold, design: .rounded))
            .offset(x: shake)
            if let total {
                Text("/\(total)")
                    .font(.system(size: size * 0.36, weight: .semibold, design: horror ? .monospaced : .rounded))
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}
