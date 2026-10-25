#if canImport(AppKit)
import AppKit
#endif
import SwiftUI
import TimeBlockKit

/// The day as rows of clock hours, 12 five-minute blocks per row.
/// A wake time of 08:30 starts halfway along the "08" row.
public struct BlockGridView: View {
    let snapshot: DaySnapshot
    let theme: MoodTheme
    /// Hour rows to show; nil shows the whole day.
    var rows: Range<Int>?
    var showsHourLabels: Bool
    /// Animation clock in seconds. 0 draws a still frame, which is all a widget can show.
    var time: Double
    /// Side of one block in points; nil scales the grid to fill the space it gets.
    var blockSize: CGFloat?
    /// What dragging across blocks logs, previewed on the block under the pointer. With none, a drag selects.
    var brush: Brush?
    /// Blocks picked out to log next, outlined until something is done with them.
    var selection: Range<Int>?
    /// Called with the blocks dragged across. Without it the grid doesn't respond to the pointer at all.
    /// With no brush, a click reports the whole run it lands on, and a double click just the one block.
    var onDrag: ((Range<Int>) -> Void)?
    /// Called when a click should drop the selection: one off the blocks, inside the selection, or a
    /// drag over exactly the selection again.
    var onDeselect: (() -> Void)?
    /// Called with the blocks to empty when Clear is picked from a logged block's right-click menu.
    var onClear: ((Range<Int>) -> Void)?
    /// Called with the selection and its new extent when a handle at either end of a selection of one activity
    /// is dragged. Without it there are no handles.
    var onResize: ((Range<Int>, Range<Int>) -> Void)?

    /// First and last block of the drag in progress.
    @State private var drag: (start: Int, end: Int)?
    @State private var hovered: Int?
    /// The block the pointer was last over, kept once it leaves so a right-click menu stays on the block it opened on.
    @State private var pointed: Int?
    /// The last single click, to spot a double click.
    @State private var lastClick: (index: Int, time: Date)?
    /// The selection's end being dragged, and the blocks it would cover now.
    @State private var resizing: (end: SelectionEnd, range: Range<Int>)?
    /// Whether the pointer is over a selection handle.
    @State private var isOverHandle = false

    private enum SelectionEnd {
        case start, end
    }

    public init(
        snapshot: DaySnapshot, theme: MoodTheme, rows: Range<Int>? = nil,
        showsHourLabels: Bool = true, time: Double = 0, blockSize: CGFloat? = nil,
        brush: Brush? = nil, selection: Range<Int>? = nil, onDrag: ((Range<Int>) -> Void)? = nil,
        onDeselect: (() -> Void)? = nil, onClear: ((Range<Int>) -> Void)? = nil,
        onResize: ((Range<Int>, Range<Int>) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.theme = theme
        self.rows = rows
        self.showsHourLabels = showsHourLabels
        self.time = time
        self.blockSize = blockSize
        self.brush = brush
        self.selection = selection
        self.onDrag = onDrag
        self.onDeselect = onDeselect
        self.onClear = onClear
        self.onResize = onResize
    }

    public static func rowCount(for snapshot: DaySnapshot) -> Int {
        let slots = snapshot.status.schedule.gridOffset + snapshot.cells.count
        return (slots + Schedule.blocksPerHour - 1) / Schedule.blocksPerHour
    }

    /// `count` rows around the current hour, for widgets too small for the whole day.
    public static func rows(around snapshot: DaySnapshot, count: Int) -> Range<Int> {
        let total = rowCount(for: snapshot)
        let slot = (snapshot.status.currentIndex ?? 0) + snapshot.status.schedule.gridOffset
        let current = min(slot / Schedule.blocksPerHour, total - 1)
        let start = max(0, min(current - count / 2, total - count))
        return start..<min(total, start + count)
    }

    public var body: some View {
        Canvas { context, size in draw(in: &context, size: size) }
            .frame(
                width: blockSize.map { GridLayout.width(side: $0, labelWidth: labelWidth) + 2 * margin },
                height: blockSize.map { GridLayout.height(side: $0, rows: resolvedRows.count) + 2 * margin })
            .overlay {
                if onDrag != nil {
                    GeometryReader { proxy in
                        let layout = layout(size: proxy.size)
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(paintGesture(size: proxy.size))
                            .contextMenu {
                                if let onClear, let pointed, let range = snapshot.clearable(at: pointed, selection: selection) {
                                    Button("Clear Blocks", systemImage: "eraser") { onClear(range) }
                                }
                            }
                            .onContinuousHover { phase in
                                if case .active(let point) = phase {
                                    hovered = layout.index(at: point, count: snapshot.cells.count, clamped: false)
                                    pointed = hovered
                                    isOverHandle = handle(at: point, layout: layout) != nil
                                } else {
                                    hovered = nil
                                    isOverHandle = false
                                }
                            }
                        if let range = labeled {
                            BlockInfo(
                                snapshot: snapshot, theme: theme, range: range,
                                brush: resizing != nil ? resizableCategory.map(Brush.category) : brush)
                                .fixedSize()
                                .position(infoPosition(for: range, layout: layout, size: proxy.size))
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            #if canImport(AppKit)
            // An open hand over a knob, closed while dragging one.
            .onChange(of: resizing != nil ? 2 : isOverHandle ? 1 : 0) { old, new in
                if old > 0 { NSCursor.pop() }
                if new > 0 { (new == 2 ? NSCursor.closedHand : NSCursor.openHand).push() }
            }
            #endif
    }

    private var dragged: Range<Int>? {
        drag.map { min($0.start, $0.end)..<(max($0.start, $0.end) + 1) }
    }

    /// What the pointer is over: with a brush, the one block it would paint; otherwise the whole selection
    /// when over it, or the run of one category around a logged block.
    private var hoveredRange: Range<Int>? {
        guard let hovered, !isOverHandle else { return nil }
        if brush != nil { return hovered..<(hovered + 1) }
        if let selection, selection.contains(hovered) { return selection }
        return snapshot.run(around: hovered)
    }

    /// Blocks the label describes: the drag in progress, else what the pointer is over, else the selection.
    private var labeled: Range<Int>? {
        resizing?.range ?? dragged ?? hoveredRange ?? selection
    }

    /// The activity the selection holds throughout, when it's logged as one, so its ends can be dragged.
    private var resizableCategory: String? {
        guard onResize != nil, brush == nil, let selection, snapshot.cells.indices.contains(selection.lowerBound),
              snapshot.cells.indices.contains(selection.upperBound - 1),
              let category = snapshot.cells[selection.lowerBound].categoryID,
              snapshot.cells[selection].allSatisfy({ $0.categoryID == category })
        else { return nil }
        return category
    }

    /// The blocks with handles: the selection, or what it's being dragged to.
    private var handled: Range<Int>? {
        resizing?.range ?? (resizableCategory != nil ? selection : nil)
    }

    /// The middle of the knob on each end of `range`: on the top-left corner of its first block and the bottom-right
    /// corner of its last, like the ends of selected text that runs over several lines.
    private func handlePoints(of range: Range<Int>, layout: GridLayout) -> (start: CGPoint, end: CGPoint) {
        let first = layout.frame(range.lowerBound)
        let last = layout.frame(range.upperBound - 1)
        let inset = layout.radius * 0.3
        return (
            CGPoint(x: first.minX + inset, y: first.minY + inset),
            CGPoint(x: last.maxX - inset, y: last.maxY - inset))
    }

    /// The knobs' size, and how far from one a press still grabs it.
    private static func knobDiameter(side: CGFloat) -> CGFloat { max(9, side * 0.55) }

    /// The selection end whose handle is under `point`, given a little room around it to grab.
    private func handle(at point: CGPoint, layout: GridLayout) -> SelectionEnd? {
        guard let range = handled else { return nil }
        let points = handlePoints(of: range, layout: layout)
        let reach = Self.knobDiameter(side: layout.side) / 2 + 5
        let isNear = { (handle: CGPoint) in hypot(point.x - handle.x, point.y - handle.y) <= reach }
        if isNear(points.end) { return .end }
        if isNear(points.start) { return .start }
        return nil
    }

    /// Just above the first highlighted block, or below it on the top row.
    private func infoPosition(for range: Range<Int>, layout: GridLayout, size: CGSize) -> CGPoint {
        let frame = layout.frame(range.lowerBound)
        let y = frame.minY > 30 ? frame.minY - 16 : frame.maxY + 16
        return CGPoint(x: min(max(frame.midX, 90), size.width - 90), y: y)
    }

    private var resolvedRows: Range<Int> { rows ?? 0..<Self.rowCount(for: snapshot) }
    private var labelWidth: CGFloat { showsHourLabels ? 24 : 0 }
    /// Room around a fixed-size grid for what reaches past the blocks, like the current block's ring.
    private var margin: CGFloat { blockSize.map { $0 * 0.4 } ?? 0 }

    private func layout(size: CGSize) -> GridLayout {
        GridLayout(
            size: size, rows: resolvedRows, offset: snapshot.status.schedule.gridOffset, labelWidth: labelWidth,
            margin: margin)
    }

    private func paintGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let layout = layout(size: size)
                let count = snapshot.cells.count
                // A press on a handle that moves drags that end; one that doesn't is an ordinary click.
                if resizing == nil, drag.map({ $0.start == $0.end }) ?? true,
                   hypot(value.translation.width, value.translation.height) >= 3, let selection,
                   let end = handle(at: value.startLocation, layout: layout) {
                    resizing = (end, selection)
                    drag = nil
                }
                if let resizing, let selection {
                    // Drag an end past the other and it stops there: a run is at least one block.
                    guard let index = layout.index(at: value.location, count: count, clamped: true) else { return }
                    let range = switch resizing.end {
                    case .start: min(index, selection.upperBound - 1)..<selection.upperBound
                    case .end: selection.lowerBound..<max(index + 1, selection.lowerBound + 1)
                    }
                    self.resizing = (resizing.end, range)
                    return
                }
                guard let start = drag?.start ?? layout.index(at: value.startLocation, count: count, clamped: false),
                      let end = layout.index(at: value.location, count: count, clamped: true)
                else { return }
                drag = (start, end)
            }
            .onEnded { _ in
                defer { drag = nil }
                if let resizing {
                    self.resizing = nil
                    if let selection, resizing.range != selection { onResize?(selection, resizing.range) }
                    return
                }
                guard let dragged else {
                    onDeselect?()
                    return
                }
                if brush != nil {
                    onDrag?(dragged)
                } else if dragged.count == 1 {
                    let index = dragged.lowerBound
                    let now = Date()
                    let isDouble = lastClick.map { $0.index == index && now.timeIntervalSince($0.time) < Self.doubleClickInterval } ?? false
                    lastClick = isDouble ? nil : (index, now)
                    if isDouble {
                        onDrag?(dragged)
                    } else if let selection, selection.contains(index) {
                        onDeselect?()
                    } else {
                        onDrag?(snapshot.run(around: index))
                    }
                } else if dragged == selection {
                    onDeselect?()
                } else {
                    onDrag?(dragged)
                }
            }
    }

    private static var doubleClickInterval: TimeInterval {
        #if canImport(AppKit)
        NSEvent.doubleClickInterval
        #else
        0.4
        #endif
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let perRow = Schedule.blocksPerHour
        let grid = layout(size: size)
        let rows = grid.rows
        guard !rows.isEmpty else { return }

        let mood = snapshot.mood
        let animated = time > 0
        let tick = Int(time * 9)
        let side = grid.side
        let gap = grid.gap
        let radius = grid.radius
        let gridWidth = grid.gridWidth
        let originX = grid.originX
        let originY = grid.originY
        let schedule = snapshot.status.schedule
        let awake = schedule.awakeBlocks
        let offset = schedule.gridOffset
        let visible = snapshot.cells.filter { rows.contains(($0.index + offset) / perRow) }
        let frame = grid.frame

        if showsHourLabels {
            let fontSize = min(11, max(7, side * 0.8))
            for row in rows {
                let first = row * perRow - offset
                let text = Text(String(format: "%02d", schedule.hour(ofRow: row)))
                    .font(.system(size: fontSize, weight: .medium, design: mood >= .uneasy ? .monospaced : .rounded))
                    .foregroundColor(first >= awake ? theme.accent : theme.secondaryText)
                let y = originY + CGFloat(row - rows.lowerBound) * (side + gap) + side / 2
                context.draw(text, at: CGPoint(x: originX - 6, y: y), anchor: .trailing)
            }
        }

        for cell in visible {
            var rect = frame(cell.index)
            var angle = 0.0
            if mood == .nightmare && cell.phase != .future {
                // A few blocks twitch when animated; the rest just sit crooked.
                let seed = animated && noise(cell.index, 99) < 0.15 ? tick : 0
                rect = rect.offsetBy(
                    dx: (noise(cell.index, 1 + seed) - 0.5) * side * 0.3,
                    dy: (noise(cell.index, 2 + seed) - 0.5) * side * 0.3)
                angle = (noise(cell.index, 3 + seed) - 0.5) * 0.5
            }
            let path = Path(roundedRect: rect, cornerRadius: radius)
                .rotated(by: angle, around: CGPoint(x: rect.midX, y: rect.midY))

            switch theme.paint(for: cell, categories: snapshot.categories) {
            case .solid(let color):
                if mood == .nightmare && cell.phase == .past && noise(cell.index, 5) < 0.1 {
                    // Dead block: only the outline is left.
                    context.stroke(path, with: .color(color.opacity(0.6)), lineWidth: max(1, side * 0.08))
                } else {
                    context.fill(path, with: .color(color))
                }
            case .planned(let color, let dashed):
                let line = max(1, side * 0.1)
                context.fill(path, with: .color(color.opacity(0.18)))
                context.stroke(
                    Path(roundedRect: rect.insetBy(dx: line / 2, dy: line / 2), cornerRadius: radius),
                    with: .color(color.opacity(0.9)),
                    style: StrokeStyle(lineWidth: line, dash: dashed ? [line * 1.6, line * 1.2] : []))
            case .empty(let color):
                context.fill(path, with: .color(color))
            }

            if onDrag != nil {
                // The brush previews on the drag or the hovered block: the new color over the old block, or a
                // dashed outline when clearing. Without a brush, dragged and selected blocks are outlined.
                let line = max(1.5, side * 0.12)
                let previewed = dragged ?? (brush != nil ? hovered.map { $0..<($0 + 1) } : nil)
                let isSelected = selection?.contains(cell.index) == true
                if let resizing, resizing.range.contains(cell.index) != isSelected {
                    // A dragged end previews like the brush: the activity's color on blocks it takes in, a dashed
                    // outline on those it lets go.
                    if isSelected {
                        context.stroke(
                            path, with: .color(theme.text), style: StrokeStyle(lineWidth: line, dash: [line * 1.5, line]))
                    } else if let color = resizableCategory.flatMap({ snapshot.categories[$0] }).map(theme.color(of:)) {
                        context.fill(path, with: .color(color.opacity(0.7)))
                        context.stroke(path, with: .color(color), lineWidth: line)
                    }
                } else if let brush, previewed?.contains(cell.index) == true {
                    if let color = brush.categoryID.flatMap({ snapshot.categories[$0] }).map(theme.color(of:)) {
                        context.fill(path, with: .color(color.opacity(0.7)))
                        context.stroke(path, with: .color(color), lineWidth: line)
                    } else {
                        context.stroke(
                            path, with: .color(theme.text), style: StrokeStyle(lineWidth: line, dash: [line * 1.5, line]))
                    }
                } else if (resizing?.range ?? dragged ?? selection)?.contains(cell.index) == true {
                    context.fill(path, with: .color(theme.text.opacity(0.2)))
                    context.stroke(path, with: .color(theme.text), lineWidth: line)
                } else if brush == nil, drag == nil, resizing == nil, let run = hoveredRange, run.contains(cell.index) {
                    // The stretch of one category (or one gap) under the pointer.
                    context.stroke(path, with: .color(theme.text.opacity(0.75)), lineWidth: line)
                }
            }

            if cell.phase == .current {
                let pulse = animated ? 0.55 + 0.45 * sin(time * 4) : 1
                let ring = frame(cell.index).insetBy(dx: -gap * 0.55, dy: -gap * 0.55)
                context.stroke(
                    Path(roundedRect: ring, cornerRadius: radius + gap * 0.55),
                    with: .color(theme.text.opacity(pulse)), lineWidth: max(1, gap * 0.45))
            }
        }

        if onDrag != nil, let range = handled {
            // A knob at each end of the selection, in the activity's color with a ring, to drag it longer or shorter.
            let points = handlePoints(of: range, layout: grid)
            let diameter = Self.knobDiameter(side: side)
            let color = resizableCategory.flatMap { snapshot.categories[$0] }.map(theme.color(of:)) ?? theme.text
            for point in [points.start, points.end] {
                let rect = CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter)
                context.fill(Path(ellipseIn: rect.offsetBy(dx: 0, dy: 1)), with: .color(.black.opacity(0.35)))
                context.fill(Path(ellipseIn: rect), with: .color(theme.text))
                context.fill(Path(ellipseIn: rect.insetBy(dx: diameter * 0.2, dy: diameter * 0.2)), with: .color(color))
            }
        }

        if mood >= .dread {
            drawDrips(in: &context, cells: visible, side: side, radius: radius, animated: animated, frame: frame)
        }

        // Bedtime line, once the day has spilled past it. Steps around a bedtime that isn't on the hour.
        let boundary = awake + offset
        let boundaryRow = boundary / perRow
        if snapshot.status.overtimeBlocks > 0, rows.contains(boundaryRow) {
            let column = boundary % perRow
            let top = originY + CGFloat(boundaryRow - rows.lowerBound) * (side + gap) - gap / 2
            let bottom = top + side + gap
            let x = originX + CGFloat(column) * (side + gap) - gap / 2
            let left = originX - 2
            let right = originX + gridWidth + 2
            let spillsToNextRow = boundary + snapshot.status.overtimeBlocks > (boundaryRow + 1) * perRow
            var line = Path()
            if column == 0 {
                line.move(to: CGPoint(x: left, y: top))
            } else {
                if spillsToNextRow {
                    line.move(to: CGPoint(x: left, y: bottom))
                    line.addLine(to: CGPoint(x: x, y: bottom))
                } else {
                    line.move(to: CGPoint(x: x, y: bottom))
                }
                line.addLine(to: CGPoint(x: x, y: top))
            }
            line.addLine(to: CGPoint(x: right, y: top))
            context.stroke(line, with: .color(theme.accent.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    private func drawDrips(
        in context: inout GraphicsContext, cells: [BlockCell], side: CGFloat, radius: CGFloat,
        animated: Bool, frame: (Int) -> CGRect
    ) {
        let nightmare = snapshot.mood == .nightmare
        for cell in cells where cell.phase != .future && noise(cell.index, 7) < (nightmare ? 0.3 : 0.16) {
            guard case .solid(let color) = theme.paint(for: cell, categories: snapshot.categories) else { continue }
            let rect = frame(cell.index)
            let reach = side * (nightmare ? 2.4 : 1.3) * (0.35 + 0.65 * noise(cell.index, 8))
            let growth = animated ? 0.85 + 0.15 * sin(time * 0.8 + noise(cell.index, 9) * 6) : 1
            let width = side * (0.16 + 0.12 * noise(cell.index, 10))
            let x = rect.minX + rect.width * (0.25 + 0.5 * noise(cell.index, 11)) - width / 2
            let stem = CGRect(x: x, y: rect.maxY - radius, width: width, height: reach * growth + radius)
            context.fill(Path(roundedRect: stem, cornerRadius: width / 2), with: .color(color))
            let drop = width * 1.5
            context.fill(
                Path(ellipseIn: CGRect(x: x + width / 2 - drop / 2, y: stem.maxY - drop * 0.8, width: drop, height: drop * 1.15)),
                with: .color(color))
        }
    }
}

/// "12:20 · Study → Exercise" or "18:20–19:25 · Social · 1h 5m · Dinner": when the blocks are, what they
/// hold (when it is one thing), how long, their note, and what the brush would make them.
private struct BlockInfo: View {
    let snapshot: DaySnapshot
    let theme: MoodTheme
    let range: Range<Int>
    let brush: Brush?

    var body: some View {
        let schedule = snapshot.status.schedule
        let cells = snapshot.cells[range.clamped(to: snapshot.cells.indices)]
        // Named when every block holds the same thing.
        let shared = cells.first.flatMap { first in cells.allSatisfy { $0.categoryID == first.categoryID } ? first : nil }
        HStack(spacing: 5) {
            let start = clock(schedule.clockMinute(ofBlock: range.lowerBound))
            Text(range.count == 1 ? start : "\(start)–\(clock(schedule.clockMinute(ofBlock: range.upperBound)))")
                .monospacedDigit()
                .foregroundStyle(theme.text)
            if let shared {
                content(of: shared)
            }
            if range.count > 1 {
                Text(durationText(blocks: range.count)).foregroundStyle(theme.secondaryText)
            }
            if let note = shared?.note, cells.allSatisfy({ $0.note == note }) {
                // The label is drawn at its natural size, so a long note is shortened here.
                Text(note.count > 40 ? note.prefix(39) + "…" : note)
                    .italic()
                    .foregroundStyle(theme.text)
            }
            if let brush, shared?.categoryID != brush.categoryID || shared == nil {
                Image(systemName: "arrow.right").foregroundStyle(theme.secondaryText)
                if let category = brush.categoryID.flatMap({ snapshot.categories[$0] }) {
                    Label(category.name, systemImage: category.symbol).foregroundStyle(theme.color(of: category))
                } else {
                    Label("Clear", systemImage: "eraser").foregroundStyle(theme.text)
                }
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(theme.backgroundTop).shadow(color: .black.opacity(0.3), radius: 4, y: 1))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.text.opacity(0.15)))
    }

    @ViewBuilder private func content(of cell: BlockCell) -> some View {
        if let category = cell.categoryID.flatMap({ snapshot.categories[$0] }) {
            Label(cell.phase == .future ? "\(category.name) (planned)" : category.name, systemImage: category.symbol)
                .foregroundStyle(theme.color(of: category))
        } else if cell.isOvertime {
            Text("Past bedtime").foregroundStyle(theme.accent)
        } else {
            Text(cell.phase == .future ? "Nothing planned" : "Unlogged").foregroundStyle(theme.secondaryText)
        }
    }

    private func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60 % 24, minute % 60)
    }
}

/// Where each block sits in a grid of `rows` hour rows fitted into `size`, `margin` in from its edges.
struct GridLayout {
    let rows: Range<Int>
    let offset: Int
    let side: CGFloat
    let gap: CGFloat
    let radius: CGFloat
    let gridWidth: CGFloat
    let originX: CGFloat
    let originY: CGFloat

    static let gapRatio: CGFloat = 0.24

    /// Grid width for blocks of `side` points.
    static func width(side: CGFloat, labelWidth: CGFloat) -> CGFloat {
        let columns = CGFloat(Schedule.blocksPerHour)
        return labelWidth + columns * side + (columns - 1) * side * gapRatio
    }

    static func height(side: CGFloat, rows: Int) -> CGFloat {
        CGFloat(rows) * side + CGFloat(max(0, rows - 1)) * side * gapRatio
    }

    init(size: CGSize, rows: Range<Int>, offset: Int, labelWidth: CGFloat, margin: CGFloat = 0) {
        let gapRatio = Self.gapRatio
        let columns = CGFloat(Schedule.blocksPerHour)
        let rowCount = CGFloat(max(1, rows.count))
        self.rows = rows
        self.offset = offset
        let available = CGSize(width: size.width - 2 * margin, height: size.height - 2 * margin)
        side = min(
            (available.width - labelWidth) / (columns + (columns - 1) * gapRatio),
            available.height / (rowCount + (rowCount - 1) * gapRatio))
        gap = side * gapRatio
        radius = side * 0.28
        gridWidth = columns * side + (columns - 1) * gap
        originX = margin + labelWidth + (available.width - labelWidth - gridWidth) / 2
        originY = margin
    }

    func frame(_ index: Int) -> CGRect {
        let slot = index + offset
        let row = slot / Schedule.blocksPerHour - rows.lowerBound
        let column = slot % Schedule.blocksPerHour
        return CGRect(
            x: originX + CGFloat(column) * (side + gap), y: originY + CGFloat(row) * (side + gap),
            width: side, height: side)
    }

    /// The block under `point`, out of `count`. Unclamped, points off the blocks give nil;
    /// clamped, they give the nearest block, so a drag can run past the grid's edge.
    func index(at point: CGPoint, count: Int, clamped: Bool) -> Int? {
        let step = side + gap
        let column = Int(((point.x - originX + gap / 2) / step).rounded(.down))
        let row = Int(((point.y - originY + gap / 2) / step).rounded(.down))
        let columns = Schedule.blocksPerHour
        if !clamped, !(0..<columns).contains(column) || !(0..<rows.count).contains(row) { return nil }
        let slot = (min(max(row, 0), rows.count - 1) + rows.lowerBound) * columns + min(max(column, 0), columns - 1)
        let index = slot - offset
        if clamped { return count > 0 ? min(max(index, 0), count - 1) : nil }
        return (0..<count).contains(index) ? index : nil
    }
}

extension Path {
    fileprivate func rotated(by angle: Double, around center: CGPoint) -> Path {
        guard angle != 0 else { return self }
        return applying(
            CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: angle)
                .translatedBy(x: -center.x, y: -center.y))
    }
}
