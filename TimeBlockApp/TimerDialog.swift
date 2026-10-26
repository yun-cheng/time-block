import AppKit
import SwiftUI
import TimeBlockKit
import TimeBlockUI

/// Starts a timer from a dialog in the middle of the window, over the day dimmed: whether it counts down, a
/// countdown's length, and the activity to time, picked from a popup. The length is typed, picked or set with blocks,
/// and can be starred to pick in a click or made what countdowns start at; counting up, there's no length to set. Start starts it, and the dialog closes then, or on Cancel, Escape or a click off it.
/// Compact, it fits a day as small as the window kept on top's: closer to its edges, and tighter inside.
struct TimerDialog: View {
    @Bindable var model: AppModel
    let theme: MoodTheme
    var isCompact = false
    @Binding var isOpen: Bool
    /// The countdown's length, kept while counting up so counting down goes back to it.
    @State private var length = CountdownLength.standard
    /// Whether the blocks show an hour as one block, for lengths past the three hours of five-minute blocks.
    @State private var showsHours = false
    /// The activity picked to time.
    @State private var chosen: String?
    @State private var showsActivities = false

    var body: some View {
        Dialog(
            width: 460, fill: theme.backgroundBottom, lift: 0.08, stroke: theme.text.opacity(0.28),
            margin: isCompact ? 10 : 32, isOpen: $isOpen
        ) {
            // Scrolling only in a window too short for all of it.
            ViewThatFits(in: .vertical) {
                content.padding(padding)
                ScrollView { content.padding(padding) }
            }
        }
        .onAppear {
            // Each time it opens, a countdown starts at the default.
            length = model.countdownDefault
            if model.countdownMinutes != nil { model.countdownMinutes = length }
            showsHours = model.countdownDefault > CountdownBlocks.blockHours * 60
        }
    }

    private var padding: CGFloat { isCompact ? 12 : 18 }
    /// Room on the left to line up with the blocks, their row labels out in it; compact, there's none to spare.
    private var blocksInset: CGFloat { isCompact ? 0 : CountdownBlocks.labelWidth }

    private var content: some View {
        let snapshot = model.snapshot
        let isGoing = chosen.map { id in model.timers.contains { $0.categoryID == id } } ?? false
        let minutes = model.countdownMinutes
        return VStack(alignment: .leading, spacing: isCompact ? 10 : 14) {
            // Their icons go first when there's no room for them.
            ViewThatFits(in: .horizontal) {
                countPicker(isCountingDown: minutes != nil, showsIcons: true)
                countPicker(isCountingDown: minutes != nil, showsIcons: false)
            }
            .frame(maxWidth: .infinity)
            if let minutes {
                lengthFields(minutes)
                blocks(minutes)
                presets(minutes)
            } else {
                Text("It counts up from zero until you stop it.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryText)
            }
            Divider()
            activityRow(snapshot, isGoing: isGoing)
            HStack {
                Spacer()
                Button("Cancel") { isOpen = false }
                    .keyboardShortcut(.cancelAction)
                Button("Start") {
                    guard let chosen else { return }
                    model.startTimer(chosen)
                    isOpen = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen == nil || isGoing)
                .help(chosen == nil ? "Choose an activity to time first" : "")
            }
        }
        .padding(.leading, blocksInset)
    }

    /// The activity picked, and whether it has a timer going, under it when there's no room beside.
    private func activityRow(_ snapshot: DaySnapshot, isGoing: Bool) -> some View {
        let going = Text("Has a timer going")
            .font(.system(size: 11))
            .foregroundStyle(theme.secondaryText)
        let picked = HStack(spacing: 10) {
            Text("Activity")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
            activityButton(snapshot)
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                picked
                if isGoing { going }
            }
            VStack(alignment: .leading, spacing: 6) {
                picked
                if isGoing { going }
            }
        }
    }

    /// Counting down or up, both named, the one picked filled in, like the tools over the activities.
    private func countPicker(isCountingDown: Bool, showsIcons: Bool) -> some View {
        HStack(spacing: 2) {
            countOption("Count Down", systemImage: "timer", isPicked: isCountingDown, showsIcon: showsIcons,
                        help: "Count down from a length, and on past zero, until you stop it") {
                model.countdownMinutes = length
            }
            countOption("Count Up", systemImage: "stopwatch", isPicked: !isCountingDown, showsIcon: showsIcons,
                        help: "Count up from zero until you stop it") {
                model.countdownMinutes = nil
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.text.opacity(0.07)))
    }

    private func countOption(
        _ title: String, systemImage: String, isPicked: Bool, showsIcon: Bool, help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if showsIcon {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isPicked ? theme.backgroundBottom : theme.secondaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(isPicked ? theme.text : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    /// The activity to time, or a prompt to choose one; a click opens the activities.
    private func activityButton(_ snapshot: DaySnapshot) -> some View {
        let category = chosen.flatMap { snapshot.categories[$0] }
        return Button {
            showsActivities = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: category?.symbol ?? "tag")
                    .foregroundStyle(category.map { theme.color(of: $0) } ?? theme.secondaryText)
                Text(category?.name ?? "Choose Activity")
                    .foregroundStyle(category == nil ? theme.secondaryText : theme.text)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.secondaryText)
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(theme.text.opacity(0.07)))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help("Choose the activity to time")
        .popover(isPresented: $showsActivities, arrowEdge: .top) {
            CategoryPalette(
                categories: snapshot.trackCategories, favorites: snapshot.favorites,
                selected: chosen.map { [.category($0)] } ?? [], theme: theme, showsClear: false,
                choose: { choice in
                    chosen = choice.categoryID
                    showsActivities = false
                })
            .padding(14)
            .frame(width: 430)
        }
    }

    /// The length's hours and minutes, typed or picked, and its blocks; under them in a dialog too narrow for one row.
    private func lengthFields(_ minutes: Int) -> some View {
        let blocks = Text("\(CountdownLength.blocks(minutes)) blocks")
            .font(.system(size: 11))
            .foregroundStyle(theme.secondaryText)
            .fixedSize()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                lengthPair
                blocks.padding(.leading, 4)
            }
            VStack(spacing: 6) {
                lengthPair
                blocks
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var lengthPair: some View {
        HStack(spacing: 10) {
            LengthField(
                title: "Hours", unit: "h", value: Binding { length / 60 } set: { setLength($0 * 60 + length % 60) },
                range: 0...(CountdownLength.longest / 60), values: Array(0...(CountdownLength.longest / 60)), theme: theme)
            LengthField(
                title: "Minutes", unit: "min", value: Binding { length % 60 } set: { setLength(length / 60 * 60 + $0) },
                range: 0...59, values: Array(stride(from: 0, to: 60, by: Schedule.blockMinutes)), theme: theme)
        }
    }

    private func blocks(_ minutes: Int) -> some View {
        let isLong = minutes > CountdownBlocks.blockHours * 60
        return VStack(spacing: 8) {
            CountdownBlocks(
                minutes: Binding { minutes } set: { setLength($0) }, showsHours: showsHours || isLong, theme: theme)
                .padding(.leading, -blocksInset)
            // Past three hours only hours fit, so there's nothing fewer to show.
            if !isLong {
                Button {
                    showsHours.toggle()
                } label: {
                    Label(showsHours ? "Fewer Hours" : "More Hours",
                          systemImage: showsHours ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryText)
                .help(showsHours ? "Show five-minute blocks, up to 3 hours" : "Show an hour to a block, up to 24 hours")
            }
        }
    }

    /// The starred lengths; and for a length that isn't starred or the default, buttons to make it so.
    private func presets(_ minutes: Int) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(model.countdownPresets, id: \.self) { preset in
                CategoryChip(
                    name: CountdownLength.text(preset), symbol: "timer", color: theme.text, theme: theme,
                    isSelected: preset == minutes
                ) {
                    setLength(preset)
                }
                .help(preset == model.countdownDefault ? "What countdowns start at" : "")
                .contextMenu {
                    Button("Unstar", systemImage: "star.slash") {
                        model.countdownPresets.removeAll { $0 == preset }
                    }
                    if preset != model.countdownDefault {
                        Button("Set as Default", systemImage: "checkmark.circle") {
                            model.countdownDefault = preset
                        }
                    }
                }
            }
            if !model.countdownPresets.contains(minutes) {
                action("Star", systemImage: "star", help: "Keep \(CountdownLength.text(minutes)) to pick in a click") {
                    model.countdownPresets = (model.countdownPresets + [minutes]).sorted()
                }
            }
            if minutes != model.countdownDefault {
                action("Set as Default", systemImage: "checkmark.circle",
                       help: "Start countdowns at \(CountdownLength.text(minutes))") {
                    model.countdownDefault = minutes
                }
            }
        }
        // Room for the selected chip's ring.
        .padding(3)
    }

    private func action(_ title: String, systemImage: String, help: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(theme.accent)
        .help(help)
    }

    /// Sets the countdown's length, from a minute to the longest.
    private func setLength(_ minutes: Int) {
        length = min(max(minutes, 1), CountdownLength.longest)
        model.countdownMinutes = length
    }
}

/// One part of a countdown's length, hours or minutes, typed or stepped with the arrow keys like the times in
/// Settings, or picked from the dropdown beside it. It takes digits only, and a number goes in as it's typed; once
/// you're done with it (Return, Tab or clicking away), one past `range` comes back into it. Clicking into it selects
/// the number, so what's typed replaces it.
private struct LengthField: View {
    let title: String
    let unit: String
    @Binding var value: Int
    /// What it can be typed as.
    let range: ClosedRange<Int>
    /// What the dropdown and the arrow keys pick from, in order.
    let values: [Int]
    let theme: MoodTheme
    @State private var text = ""
    @State private var isEditing = false

    var body: some View {
        HStack(spacing: 4) {
            NumberField(
                title: title, text: $text, isEditing: $isEditing, color: NSColor(theme.text), commit: commit, step: step)
                .frame(width: 34)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 7).fill(theme.text.opacity(0.07)))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(theme.accent.opacity(isEditing ? 0.8 : 0), lineWidth: 1.5))
                .onChange(of: text) {
                    // Digits only, as many as the largest it can be has.
                    let digits = String(text.filter(\.isASCII).filter(\.isNumber).prefix(String(range.upperBound).count))
                    if digits != text {
                        text = digits
                        return
                    }
                    if isEditing, let typed = Int(text), range.contains(typed) { value = typed }
                }
            Text(unit)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.secondaryText)
            Menu {
                ForEach(values, id: \.self) { option in
                    Button("\(option) \(unit)") { value = option }
                }
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Choose \(title.lowercased())")
            .accessibilityLabel("Choose \(title.lowercased())")
        }
        // Whole, the room around the row going first: a row sharing its width out would cut the unit off.
        .fixedSize()
        .onAppear { text = "\(value)" }
        .onChange(of: value) {
            if !isEditing { text = "\(value)" }
        }
    }

    /// Takes the typed number, kept in range, or puts back the one held.
    private func commit() {
        if let typed = Int(text) { value = min(max(typed, range.lowerBound), range.upperBound) }
        text = "\(value)"
    }

    /// Goes to the next of the values up or down, from 21 to 25 or 20.
    private func step(_ direction: Int) {
        commit()
        let next = direction > 0 ? values.first { $0 > value } : values.last { $0 < value }
        if let next { value = next }
        text = "\(value)"
    }
}

/// A borderless number field that selects what it holds when clicked into, which SwiftUI's text field can't: the
/// click puts the caret in after anything SwiftUI could do. ↑ and ↓ step it.
private struct NumberField: NSViewRepresentable {
    let title: String
    @Binding var text: String
    @Binding var isEditing: Bool
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
        field.font = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        field.textColor = color
        field.stringValue = text
        field.delegate = context.coordinator
        field.setAccessibilityLabel(title)
        field.onReturn = { [unowned coordinator = context.coordinator] in coordinator.parent.commit() }
        return field
    }

    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
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
