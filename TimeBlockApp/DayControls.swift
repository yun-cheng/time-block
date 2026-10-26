import SwiftUI
import TimeBlockKit
import TimeBlockUI

/// A control drawn in the day's own colors rather than as a system button: its secondary text, brighter under the
/// pointer over a faint capsule, and filled when it's on.
struct DayButtonStyle: ButtonStyle {
    let theme: MoodTheme
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, theme: theme, isOn: isOn)
    }

    private struct Styled: View {
        let configuration: Configuration
        let theme: MoodTheme
        let isOn: Bool
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let isLit = isEnabled && (isOn || isHovered)
            configuration.label
                .foregroundStyle(isLit ? theme.text : theme.secondaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(theme.text.opacity(fill)))
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Capsule())
                .onHover { isHovered = $0 }
        }

        private var fill: Double {
            guard isEnabled else { return 0 }
            if configuration.isPressed { return 0.2 }
            return isOn ? 0.14 : isHovered ? 0.08 : 0
        }
    }
}

/// Goes back and forth between days, as in Calendar: ‹ and › either side of the date shown, which picks one from a
/// calendar, and Today to come back.
struct DayPicker: View {
    @Bindable var model: AppModel
    let theme: MoodTheme
    @State private var showsCalendar = false

    var body: some View {
        HStack(spacing: 0) {
            Button {
                model.showDay(-1)
            } label: {
                Label("Previous Day", systemImage: "chevron.left")
            }
            .help("Previous Day")
            Button {
                showsCalendar.toggle()
            } label: {
                Text(title).monospacedDigit()
            }
            .help("Go to a Day")
            .popover(isPresented: $showsCalendar, arrowEdge: .bottom) {
                DatePicker("Day", selection: date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding()
            }
            Button {
                model.showDay(1)
            } label: {
                Label("Next Day", systemImage: "chevron.right")
            }
            .help("Next Day")
            if !model.isShowingToday {
                Button("Today") { model.showToday() }
                    .buttonStyle(DayButtonStyle(theme: theme, isOn: true))
                    .help("Go to Today")
                    .padding(.leading, 4)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(DayButtonStyle(theme: theme))
        // The day's own padding lines the date up with the counter under it, not the button's.
        .padding(.leading, -6)
    }

    /// The day shown: "Sat 24 Oct", with the year when it isn't this one.
    private var title: String {
        let date = DayID.date(model.shownDay) ?? .now
        let format = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        let isThisYear = model.shownDay.prefix(4) == model.dayLog.day.prefix(4)
        return date.formatted(isThisYear ? format : format.year())
    }

    private var date: Binding<Date> {
        Binding {
            DayID.date(model.shownDay) ?? .now
        } set: { date in
            model.show(DayID.string(from: date))
            showsCalendar = false
        }
    }
}

/// Switches between views of the day: the one shown named beside its symbol, the others just their symbols.
struct TrackSwitch: View {
    @Binding var track: Track
    let theme: MoodTheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Track.allCases, id: \.self) { option in
                Button {
                    track = option
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: option.symbol)
                        if option == track {
                            Text(option.name)
                        }
                    }
                }
                .buttonStyle(DayButtonStyle(theme: theme, isOn: option == track))
                .accessibilityLabel(option.name)
                .help(option.name)
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.trailing, -6)
    }
}

/// Offers to take back the last change to the blocks, or put back the one just undone, for a few seconds after it.
struct UndoToast: View {
    /// What Undo and Redo would do now ("Undo Move Blocks"), nil when there's nothing to.
    let undo: String?
    let redo: String?
    /// Whether the last change was an undo, which makes Redo the one named.
    let wasUndo: Bool
    let perform: (_ isRedo: Bool) -> Void

    var body: some View {
        HStack(spacing: 2) {
            if wasUndo {
                button(redo, isRedo: true, titled: true)
                button(undo, isRedo: false, titled: false)
            } else {
                button(undo, isRedo: false, titled: true)
                button(redo, isRedo: true, titled: false)
            }
        }
        .padding(4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
    }

    @ViewBuilder
    private func button(_ title: String?, isRedo: Bool, titled: Bool) -> some View {
        if let title {
            Button {
                perform(isRedo)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isRedo ? "arrow.uturn.forward" : "arrow.uturn.backward")
                    if titled {
                        Text(title)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Capsule())
            }
            .buttonStyle(.borderless)
            .help(title)
        }
    }
}
