import SwiftUI
import TimeBlockKit

/// Starts and stops the timers that log activities live.
public struct TimerControls {
    public var timers: [LiveTimer]
    /// What new timers count down from, in minutes, or nil to count up.
    public var countdown: Binding<Int?>
    /// The countdown lengths to pick from, in minutes.
    public var presets: [Int]
    /// Starts a timer of an activity, unless it has one going.
    public var start: (String) -> Void
    /// Stops a timer, logging what it ran.
    public var stop: (UUID) -> Void
    /// Drops a timer without logging what it ran.
    public var delete: (UUID) -> Void

    public init(
        timers: [LiveTimer], countdown: Binding<Int?>, presets: [Int] = CountdownLength.standardPresets,
        start: @escaping (String) -> Void, stop: @escaping (UUID) -> Void, delete: @escaping (UUID) -> Void
    ) {
        self.timers = timers
        self.countdown = countdown
        self.presets = presets
        self.start = start
        self.stop = stop
        self.delete = delete
    }
}

/// The timers going, each with its activity, its time (counting up, or down and then on past zero, in the accent
/// color) and buttons to stop it and to delete it. The times go on each second.
public struct TimerList: View {
    let controls: TimerControls
    let categories: [String: BlockCategory]
    let theme: MoodTheme
    /// The timer whose delete is waiting to be confirmed.
    @State private var deleting: LiveTimer?

    public init(controls: TimerControls, categories: [String: BlockCategory], theme: MoodTheme) {
        self.controls = controls
        self.categories = categories
        self.theme = theme
    }

    public var body: some View {
        SecondClock { date in
            VStack(alignment: .leading, spacing: 4) {
                ForEach(controls.timers) { timer in
                    row(timer, at: date)
                }
            }
        }
        .alert(
            "Delete the \(deleting.map { name(of: $0) } ?? "") timer?",
            isPresented: Binding { deleting != nil } set: { if !$0 { deleting = nil } },
            presenting: deleting
        ) { timer in
            Button("Delete", role: .destructive) { controls.delete(timer.id) }
            Button("Cancel", role: .cancel) {}
        } message: { timer in
            Text("The \(Self.clock(timer.elapsed(at: .now))) it has run won't be logged.")
        }
    }

    private func name(of timer: LiveTimer) -> String {
        categories[timer.categoryID]?.name ?? timer.categoryID
    }

    private func row(_ timer: LiveTimer, at date: Date) -> some View {
        let category = categories[timer.categoryID]
        let remaining = timer.remaining(at: date)
        let isOver = (remaining ?? 0) < 0
        return HStack(spacing: 8) {
            Label(name(of: timer), systemImage: category?.symbol ?? "questionmark")
                .foregroundStyle(category.map { theme.color(of: $0) } ?? theme.text)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: timer.countdown == nil ? "stopwatch" : "timer")
                .foregroundStyle(theme.secondaryText)
                .help(timer.countdown.map { "Counting down from \(Int($0) / 60) min" } ?? "Counting up")
            Text(Self.clock(remaining ?? timer.elapsed(at: date)))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(isOver ? theme.accent : theme.text)
                .help(isOver ? "Over its countdown" : "")
            Button {
                controls.stop(timer.id)
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 16)
            }
            .help("Stop")
            Button {
                deleting = timer
            } label: {
                Image(systemName: "trash")
                    .frame(width: 16)
            }
            .help("Delete: drop it, leaving what it ran unlogged")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(theme.text)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(theme.text.opacity(0.07)))
    }

    /// "4:07", "1:02:03", or "−2:13" past zero.
    static func clock(_ interval: TimeInterval) -> String {
        let seconds = Int(abs(interval).rounded(.down))
        let sign = interval <= -1 ? "\u{2212}" : ""
        let (hours, minutes) = (seconds / 3600, seconds / 60 % 60)
        return hours > 0
            ? String(format: "%@%d:%02d:%02d", sign, hours, minutes, seconds % 60)
            : String(format: "%@%d:%02d", sign, minutes, seconds % 60)
    }
}

/// Sets a countdown the way the day is drawn: an hour to a row of five-minute blocks, filled up to the length, three
/// hours of them. Showing hours, an hour is one big block instead, up to 24, over a row of the minutes past them; a
/// row of hours shows once the one before it is filled. Click a block to fill up to it, or the last one filled to
/// empty it; drag to fill across. Under the pointer, the blocks show what a click would set.
public struct CountdownBlocks: View {
    @Binding var minutes: Int
    let showsHours: Bool
    let theme: MoodTheme
    @State private var width: CGFloat = 400
    /// The block under the pointer.
    @State private var hovered: Cell?
    /// The block a press started on, and whether it was the last one filled then.
    @State private var pressed: (cell: Cell, wasLast: Bool)?

    public init(minutes: Binding<Int>, showsHours: Bool, theme: MoodTheme) {
        _minutes = minutes
        self.showsHours = showsHours
        self.theme = theme
    }

    /// The longest countdown that fits as rows of five-minute blocks.
    public static let blockHours = 3
    private static let columns = 60 / Schedule.blockMinutes
    private static let hoursPerRow = columns / 2
    /// Room on the left for each row's label, which views around it can leave to line up with the blocks.
    public static let labelWidth: CGFloat = 26

    private enum Kind { case block, hour, minute }

    private struct Cell: Equatable {
        var kind: Kind
        var index: Int
    }

    /// Small blocks are as wide as a row allows, with gaps in proportion and a wider one at the half hour, as on the
    /// grid; an hour's block is two of them wide.
    private var side: CGFloat {
        (width - Self.labelWidth) / (CGFloat(Self.columns) + CGFloat(Self.columns - 1) * 0.15 + 0.3)
    }
    private var gap: CGFloat { side * 0.15 }
    private var bigSide: CGFloat { side * 2 + gap }
    /// The rows of hours shown: two, and one more past the last filled, up to all of them.
    private var hourRows: Int {
        min(max(2, minutes / 60 / Self.hoursPerRow + 1), CountdownLength.longest / 60 / Self.hoursPerRow)
    }
    /// Where the row of minutes starts, under the hours.
    private var minutesY: CGFloat { CGFloat(hourRows) * (bigSide + gap) + gap * 2 }

    private var height: CGFloat {
        showsHours
            ? minutesY + side
            : CGFloat(Self.blockHours) * side + CGFloat(Self.blockHours - 1) * gap
    }

    private var cells: [Cell] {
        showsHours
            ? (0..<(hourRows * Self.hoursPerRow)).map { Cell(kind: .hour, index: $0) }
                + (0..<Self.columns).map { Cell(kind: .minute, index: $0) }
            : (0..<(Self.blockHours * Self.columns)).map { Cell(kind: .block, index: $0) }
    }

    /// How many blocks of a kind are filled, any part of one filling it.
    private func count(_ kind: Kind) -> Int {
        switch kind {
        case .block: CountdownLength.blocks(minutes)
        case .hour: minutes / 60
        case .minute: CountdownLength.blocks(minutes % 60)
        }
    }

    /// The length with `filled` blocks of a kind, the rest kept, from one block to the longest.
    private func length(_ kind: Kind, filled: Int) -> Int {
        let value = switch kind {
        case .block: filled * Schedule.blockMinutes
        case .hour: filled * 60 + minutes % 60
        case .minute: minutes / 60 * 60 + filled * Schedule.blockMinutes
        }
        return min(max(value, Schedule.blockMinutes), CountdownLength.longest)
    }

    public var body: some View {
        Canvas { context, _ in
            func label(_ text: String, _ y: CGFloat) {
                context.draw(
                    Text(text).font(.system(size: 10, weight: .medium)).foregroundColor(theme.secondaryText),
                    at: CGPoint(x: 0, y: y), anchor: .leading)
            }
            if showsHours {
                label("h", (minutesY - gap * 2) / 2)
                label("min", minutesY + side / 2)
            } else {
                for row in 0..<Self.blockHours {
                    label("\(row)h", CGFloat(row) * (side + gap) + side / 2)
                }
            }
            for cell in cells {
                let filled = count(cell.kind)
                let isFilled = cell.index < filled
                let preview = hovered.flatMap { $0.kind == cell.kind ? cell.index <= $0.index : nil } ?? isFilled
                let color: Color = switch (isFilled, preview) {
                case (true, true): theme.accent
                case (true, false): theme.accent.opacity(0.45)
                case (false, true): theme.accent.opacity(0.35)
                case (false, false): theme.emptyBlock
                }
                let rect = frame(cell)
                context.fill(Path(roundedRect: rect, cornerRadius: rect.width * 0.2), with: .color(color))
            }
        }
        .frame(height: height)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active(let point) = phase, point.x >= Self.labelWidth {
                hovered = cell(at: point)
            } else {
                hovered = nil
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let start = pressed?.cell ?? cell(at: drag.location)
                    if pressed == nil {
                        pressed = (start, start.index + 1 == count(start.kind))
                    }
                    let cell = cell(at: drag.location, of: start.kind)
                    hovered = cell
                    minutes = length(cell.kind, filled: cell.index + 1)
                }
                .onEnded { drag in
                    // A click on the last block filled empties it.
                    if let pressed, pressed.wasLast, cell(at: drag.location, of: pressed.cell.kind) == pressed.cell {
                        minutes = length(pressed.cell.kind, filled: pressed.cell.index)
                    }
                    pressed = nil
                })
        .accessibilityElement()
        .accessibilityLabel("Countdown length")
        .accessibilityValue(CountdownLength.text(minutes))
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? Schedule.blockMinutes : -Schedule.blockMinutes
            minutes = min(max(minutes + step, Schedule.blockMinutes), CountdownLength.longest)
        }
    }

    private func frame(_ cell: Cell) -> CGRect {
        let x = { (column: Int) in
            Self.labelWidth + CGFloat(column) * (side + gap) + (column >= Self.columns / 2 ? side * 0.3 : 0)
        }
        switch cell.kind {
        case .block:
            let (row, column) = (cell.index / Self.columns, cell.index % Self.columns)
            return CGRect(x: x(column), y: CGFloat(row) * (side + gap), width: side, height: side)
        case .hour:
            let (row, column) = (cell.index / Self.hoursPerRow, cell.index % Self.hoursPerRow * 2)
            return CGRect(x: x(column), y: CGFloat(row) * (bigSide + gap), width: x(column + 1) + side - x(column),
                          height: bigSide)
        case .minute:
            return CGRect(x: x(cell.index), y: minutesY, width: side, height: side)
        }
    }

    /// The block at `point`, or the nearest one, of `kind` when given.
    private func cell(at point: CGPoint, of kind: Kind? = nil) -> Cell {
        let distance = { (rect: CGRect) in
            hypot(max(rect.minX - point.x, 0, point.x - rect.maxX), max(rect.minY - point.y, 0, point.y - rect.maxY))
        }
        return cells.filter { kind == nil || $0.kind == kind }.min { distance(frame($0)) < distance(frame($1)) }!
    }
}
