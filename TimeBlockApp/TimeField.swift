import SwiftUI
import TimeBlockKit

/// A time of day as its hour and minutes, each typed, stepped with the arrow keys (an hour, or a 5-minute block), or
/// picked from the dropdown in its box, like a countdown's length: "[07 ⌄] : [30 ⌄]". Minutes typed between blocks go
/// to the nearest once you're done with them (Return, Tab or clicking away).
struct TimeField: View {
    let title: String
    /// Minutes since midnight, on a block boundary.
    @Binding var minute: Int

    init(_ title: String, minute: Binding<Int>) {
        self.title = title
        _minute = minute
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                NumberPicker(
                    title: "\(title) hour", value: Binding { minute / 60 } set: { minute = $0 * 60 + minute % 60 },
                    range: 0...23, values: Array(0...23), digits: 2, style: .settings)
                Text(":")
                    .foregroundStyle(.secondary)
                NumberPicker(
                    title: "\(title) minutes", value: Binding { minute % 60 } set: { minute = minute / 60 * 60 + $0 },
                    range: 0...59, values: Array(stride(from: 0, to: 60, by: Schedule.blockMinutes)), snaps: true,
                    digits: 2, style: .settings)
            }
        }
    }
}
