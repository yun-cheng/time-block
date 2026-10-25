import AppKit
import SwiftUI
import TimeBlockKit

/// A time of day you type, or step with the arrow keys: a block at a time on the minutes, an hour on the hours.
/// There are no stepper arrows to miss. A typed time rounds to the nearest 5-minute block once you're done with
/// it (Return, Tab, clicking into another field, or a moment's pause), not digit by digit. The dropdown beside it
/// picks from a short scrolling list of times every 15 minutes, opening at the time held.
struct TimeField: View {
    let title: String
    /// Minutes since midnight, on a block boundary.
    @Binding var minute: Int
    @State private var showsTimes = false

    init(_ title: String, minute: Binding<Int>) {
        self.title = title
        _minute = minute
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 2) {
                BlockTimePicker(title: title, minute: $minute)
                    .fixedSize()
                Button {
                    // Finish a time being typed, so the pick replaces it.
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    showsTimes = true
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Choose a time")
                .accessibilityLabel("Choose \(title)")
                .popover(isPresented: $showsTimes, arrowEdge: .bottom) {
                    TimeList(minute: $minute) { showsTimes = false }
                }
            }
        }
    }
}

/// The date picker's text field, without its stepper.
private struct BlockTimePicker: NSViewRepresentable {
    let title: String
    @Binding var minute: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.datePickerStyle = .textField
        field.datePickerElements = .hourMinute
        field.setAccessibilityLabel(title)
        field.dateValue = Self.date(for: minute)
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed(_:))
        field.onCommit = { [unowned coordinator = context.coordinator] in coordinator.commit(field) }
        return field
    }

    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        // Leave a time being typed alone until it's done.
        guard !context.coordinator.isTyping else { return }
        let date = Self.date(for: minute)
        if field.dateValue != date { field.dateValue = date }
    }

    static func date(for minute: Int) -> Date {
        Calendar.current.startOfDay(for: .now).addingTimeInterval(Double(minute * 60))
    }

    static func minute(of date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: BlockTimePicker
        /// Whether the field holds a typed time that isn't rounded and saved yet.
        private(set) var isTyping = false
        /// Rounds a typed time after a pause, for when you stop typing without leaving the field.
        private var pause: Task<Void, Never>?

        init(_ parent: BlockTimePicker) {
            self.parent = parent
        }

        @objc func changed(_ field: Field) {
            guard field.isStepping else {
                isTyping = true
                pause?.cancel()
                pause = Task { [weak self, weak field] in
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled, let field else { return }
                    self?.commit(field)
                }
                return
            }
            // An arrow key moves the minutes by one; make that a block.
            let minute = Schedule.snappedMinute(editing: parent.minute, to: BlockTimePicker.minute(of: field.dateValue))
            parent.minute = minute
            field.dateValue = BlockTimePicker.date(for: minute)
        }

        func commit(_ field: Field) {
            pause?.cancel()
            guard isTyping else { return }
            isTyping = false
            let day = 24 * 60
            let typed = BlockTimePicker.minute(of: field.dateValue)
            let minute = (typed + Schedule.blockMinutes / 2) / Schedule.blockMinutes * Schedule.blockMinutes % day
            parent.minute = minute
            field.dateValue = BlockTimePicker.date(for: minute)
        }
    }

    /// Tells arrow-key steps from typing, and says when typing is done.
    final class Field: NSDatePicker {
        private(set) var isStepping = false
        var onCommit: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            switch event.specialKey {
            case .upArrow?, .downArrow?:
                onCommit?()
                isStepping = true
                super.keyDown(with: event)
                isStepping = false
            case .carriageReturn?, .enter?:
                onCommit?()
            case .tab?, .backTab?:
                onCommit?()
                super.keyDown(with: event)
            default:
                super.keyDown(with: event)
            }
        }

        // Return can also press a default button before it reaches keyDown; round the time first.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if [.carriageReturn, .enter].contains(event.specialKey), window?.firstResponder === self { onCommit?() }
            return super.performKeyEquivalent(with: event)
        }

        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned { onCommit?() }
            return resigned
        }
    }
}

/// Times every 15 minutes in a short list that scrolls, like a menu, opening at the time held, which is shaded
/// when it's on the list.
private struct TimeList: View {
    @Binding var minute: Int
    let done: () -> Void
    @State private var hovered: Int?

    private static let stepMinutes = 15
    private static let times = Array(stride(from: 0, to: 24 * 60, by: stepMinutes))
    /// The margin around the rows; the scroll bar shows in the one on the right, clear of them.
    private static let lane: CGFloat = 12

    var body: some View {
        ScrollViewReader { proxy in
            // AppKit's scroll bar would sit in a wide dark track and run out past the popover's bubble; this one
            // stays in the margin.
            AppScrollView(lane: Self.lane) {
                VStack(spacing: 0) {
                    ForEach(Self.times, id: \.self) { time in
                        row(time)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, Self.lane)
            }
            // As wide as the times, no wider.
            .fixedSize(horizontal: true, vertical: false)
            .frame(height: 236)
            .onAppear { proxy.scrollTo(minute / Self.stepMinutes * Self.stepMinutes, anchor: .center) }
        }
    }

    private func row(_ time: Int) -> some View {
        let isHovered = hovered == time
        let isCurrent = time == minute
        return Button {
            minute = time
            done()
        } label: {
            // As wide as the widest time and right-aligned in it, so the colons and AM/PM line up whether the hour
            // has one digit or two.
            ZStack(alignment: .trailing) {
                Self.label(for: Self.widest).hidden()
                Self.label(for: time)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .foregroundStyle(isHovered ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(
                isHovered ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary.opacity(isCurrent ? 1 : 0)),
                in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside {
                hovered = time
            } else if hovered == time {
                hovered = nil
            }
        }
        .id(time)
    }

    /// 10:45 PM, or 22:45: two digits in the hour, and PM where there is one.
    private static let widest = 22 * 60 + 45

    private static func label(for time: Int) -> some View {
        Text(BlockTimePicker.date(for: time), format: .dateTime.hour().minute())
            .monospacedDigit()
    }
}
