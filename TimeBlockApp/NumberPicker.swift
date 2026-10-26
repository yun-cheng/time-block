import AppKit
import SwiftUI
import TimeBlockKit
import TimeBlockUI

/// A number typed, stepped with the arrow keys, or picked from the dropdown beside it: an hour or minutes of a time
/// or a length. It takes digits only, and a number goes in as it's typed; once you're done with it (Return, Tab or
/// clicking away), one past `range` comes back into it. Clicking into it selects the number, so what's typed replaces
/// it.
struct NumberPicker: View {
    let title: String
    /// Shown after the number, as "h" or "min"; none for a time's hour and minutes.
    var unit: String?
    @Binding var value: Int
    /// What it can be typed as.
    let range: ClosedRange<Int>
    /// What the dropdown and the arrow keys pick from, in order.
    let values: [Int]
    /// Whether only `values` go in: a number typed between them waits until you're done, then goes to the nearest.
    var snaps = false
    /// How many digits it shows, with zeros in front: 2 for "07".
    var digits = 1
    let style: Style

    @State private var text = ""
    @State private var isEditing = false

    /// Large in a dialog drawn in the day's colors, or the size and colors of the settings around it.
    struct Style {
        var fontSize: CGFloat
        var weight: Font.Weight
        var text: Color
        var nsText: NSColor
        var secondary: Color
        var accent: Color

        static func dialog(_ theme: MoodTheme) -> Style {
            Style(
                fontSize: 22, weight: .semibold, text: theme.text, nsText: NSColor(theme.text),
                secondary: theme.secondaryText, accent: theme.accent)
        }

        static let settings = Style(
            fontSize: 13, weight: .regular, text: .primary, nsText: .labelColor, secondary: .secondary,
            accent: .accentColor)

        var isLarge: Bool { fontSize > 16 }
    }

    var body: some View {
        let corner: CGFloat = style.isLarge ? 7 : 5
        HStack(spacing: style.isLarge ? 4 : 3) {
            // One box, like a combo box: the number to type, and the dropdown inside it, at its end.
            HStack(spacing: 0) {
                NumberField(
                    title: title, text: $text, isEditing: $isEditing, font: font, color: style.nsText, commit: commit,
                    step: step)
                    .frame(width: fieldWidth)
                    .padding(.leading, style.isLarge ? 8 : 5)
                    .onChange(of: text) {
                        // Digits only, as many as the largest it can be has.
                        let typed = String(text.filter(\.isASCII).filter(\.isNumber).prefix(maxDigits))
                        if typed != text {
                            text = typed
                            return
                        }
                        if isEditing, let number = Int(text), range.contains(number),
                           !snaps || values.contains(number) {
                            value = number
                        }
                    }
                dropdown
            }
            .padding(.vertical, style.isLarge ? 4 : 2)
            .background(RoundedRectangle(cornerRadius: corner).fill(style.text.opacity(0.07)))
            .overlay(
                RoundedRectangle(cornerRadius: corner)
                    .strokeBorder(style.accent.opacity(isEditing ? 0.8 : 0), lineWidth: 1.5))
            if let unit {
                Text(unit)
                    .font(.system(size: style.isLarge ? 14 : 12, weight: .medium))
                    .foregroundStyle(style.secondary)
            }
        }
        // Whole, the room around the row going first: a row sharing its width out would cut the unit off.
        .fixedSize()
        .onAppear { text = format(value) }
        .onChange(of: value) {
            if !isEditing { text = format(value) }
        }
    }

    /// The values to pick from, opened by the chevron at the end of the box.
    private var dropdown: some View {
        Menu {
            ForEach(values, id: \.self) { option in
                Button([format(option), unit].compactMap { $0 }.joined(separator: " ")) { value = option }
            }
        } label: {
            // Drawn small, like the activity button's: a borderless menu's button is the size of a control.
            Image(systemName: "chevron.down")
                .font(.system(size: style.isLarge ? 11 : 9, weight: .bold))
                .foregroundStyle(style.secondary)
                .padding(.leading, style.isLarge ? 5 : 3)
                .padding(.trailing, style.isLarge ? 8 : 5)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: true, vertical: false)
        .help("Choose \(title.lowercased())")
        .accessibilityLabel("Choose \(title.lowercased())")
    }

    private var font: NSFont {
        .monospacedDigitSystemFont(ofSize: style.fontSize, weight: style.weight == .semibold ? .semibold : .regular)
    }

    private var maxDigits: Int { max(digits, String(range.upperBound).count) }

    /// Room for the most digits it takes, no more; a dialog's a little more, as it always was.
    private var fieldWidth: CGFloat {
        if style.isLarge { return 34 }
        let digit = ("0" as NSString).size(withAttributes: [.font: font]).width
        return ceil(digit * CGFloat(maxDigits)) + 4
    }

    private func format(_ number: Int) -> String {
        String(format: "%0\(digits)d", number)
    }

    /// Takes the typed number, kept in range (and at the nearest of `values`, when it snaps), or puts back the one
    /// held.
    private func commit() {
        if let typed = Int(text) {
            let kept = min(max(typed, range.lowerBound), range.upperBound)
            value = snaps ? values.min { abs($0 - kept) < abs($1 - kept) } ?? kept : kept
        }
        text = format(value)
    }

    /// Goes to the next of the values up or down, from 21 to 25 or 20.
    private func step(_ direction: Int) {
        commit()
        let next = direction > 0 ? values.first { $0 > value } : values.last { $0 < value }
        if let next { value = next }
        text = format(value)
    }
}

/// Hours and minutes of a length, each typed or picked, like a countdown's: "1 h 30 min". The minutes go in blocks.
struct DurationPicker: View {
    let title: String
    @Binding var minutes: Int
    /// The least and most it can be, in minutes.
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 8) {
            NumberPicker(
                title: "\(title) hours", unit: "h", value: Binding { minutes / 60 } set: { set($0 * 60 + minutes % 60) },
                range: 0...(range.upperBound / 60), values: Array(0...(range.upperBound / 60)), style: .settings)
            NumberPicker(
                title: "\(title) minutes", unit: "min",
                value: Binding { minutes % 60 } set: { set(minutes / 60 * 60 + $0) }, range: 0...59,
                values: Array(stride(from: 0, to: 60, by: Schedule.blockMinutes)), snaps: true, style: .settings)
        }
    }

    private func set(_ new: Int) {
        minutes = min(max(new, range.lowerBound), range.upperBound)
    }
}

/// A borderless number field that selects what it holds when clicked into, which SwiftUI's text field can't: the
/// click puts the caret in after anything SwiftUI could do. ↑ and ↓ step it.
private struct NumberField: NSViewRepresentable {
    let title: String
    @Binding var text: String
    @Binding var isEditing: Bool
    let font: NSFont
    let color: NSColor
    let commit: () -> Void
    let step: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .right
        field.font = font
        field.textColor = color
        field.stringValue = text
        field.delegate = context.coordinator
        field.setAccessibilityLabel(title)
        field.onReturn = { [unowned coordinator = context.coordinator] in coordinator.parent.commit() }
        return field
    }

    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        field.font = font
        field.textColor = color
        if field.stringValue != text { field.stringValue = text }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NumberField

        init(_ parent: NumberField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.isEditing = true
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isEditing = false
            parent.commit()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                parent.step(1)
            case #selector(NSResponder.moveDown(_:)):
                parent.step(-1)
            default:
                return false
            }
            textView.selectAll(nil)
            return true
        }
    }

    final class Field: NSTextField {
        var onReturn: (() -> Void)?

        // The click starts editing and places the caret, and returns once the button is up; then select it all.
        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            currentEditor()?.selectAll(nil)
        }

        // Return can press the default button before the field sees it; take the typed number first.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if [.carriageReturn, .enter].contains(event.specialKey), currentEditor() != nil { onReturn?() }
            return super.performKeyEquivalent(with: event)
        }
    }
}
