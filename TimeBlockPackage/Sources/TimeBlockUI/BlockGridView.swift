#if canImport(AppKit)
import AppKit
#endif
import SwiftUI
import TimeBlockKit

/// The day as rows of clock hours, 12 five-minute blocks per row, split and labeled as `DaySnapshot.grid` says.
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
    /// Whether activities are added to what blocks hold, shown by the add pointer over the blocks.
    var isAdding: Bool
    /// Blocks picked out to log next, outlined until something is done with them.
    var selection: Range<Int>?
    /// The one activity of the selected blocks picked out, when a card of a stack was clicked; nil when the selection
    /// is everything they hold.
    var selectedLayer: String?
    /// Called with the blocks dragged across. Without it the grid doesn't respond to the pointer at all.
    /// With no brush, a click reports the whole run it lands on, and a double click just the one block.
    var onDrag: ((Range<Int>) -> Void)?
    /// Called when a click should drop the selection: one off the blocks, inside the selection, or a
    /// drag over exactly the selection again.
    var onDeselect: (() -> Void)?
    /// Called with the blocks to empty, and the one activity to take off them (nil for everything), when Clear is
    /// picked from a logged block's right-click menu.
    var onClear: ((Range<Int>, String?) -> Void)?
    /// Called with the selection and its new extent when a handle at either end of a selection of one activity
    /// is dragged. Without it there are no handles.
    var onResize: ((Range<Int>, Range<Int>) -> Void)?
    /// Called with the selection and how many blocks along it was dragged, when a selection holding something logged
    /// is dragged from inside. Without it a drag there selects afresh.
    var onMove: ((Range<Int>, Int) -> Void)?
    /// Called with an activity's run and the activity when one card of a stack is clicked. Without it a click there
    /// selects the whole stack.
    var onSelectLayer: ((Range<Int>, String) -> Void)?

    /// First and last block of the drag in progress.
    @State private var drag: (start: Int, end: Int)?
    @State private var hovered: Int?
    /// The card of a stack the pointer is over, by activity.
    @State private var hoveredLayer: String?
    /// The block the pointer was last over, and the card of it, kept once it leaves so a right-click menu stays on
    /// the block it opened on.
    @State private var pointed: Int?
    @State private var pointedLayer: String?
    /// The last single click, to spot a double click.
    @State private var lastClick: (index: Int, time: Date)?
    /// The selection's end being dragged, and the blocks it would cover now.
    @State private var resizing: (end: SelectionEnd, range: Range<Int>)?
    /// The block a drag inside the selection began on, and how many blocks along it has moved the selection.
    @State private var moving: (from: Int, offset: Int)?
    /// Whether the pointer is over a selection handle.
    @State private var isOverHandle = false

    private enum SelectionEnd {
        case start, end
    }

    public init(
        snapshot: DaySnapshot, theme: MoodTheme, rows: Range<Int>? = nil,
        showsHourLabels: Bool = true, time: Double = 0, blockSize: CGFloat? = nil,
        brush: Brush? = nil, isAdding: Bool = false, selection: Range<Int>? = nil, selectedLayer: String? = nil,
        onDrag: ((Range<Int>) -> Void)? = nil, onDeselect: (() -> Void)? = nil, onClear: ((Range<Int>, String?) -> Void)? = nil,
        onResize: ((Range<Int>, Range<Int>) -> Void)? = nil, onMove: ((Range<Int>, Int) -> Void)? = nil,
        onSelectLayer: ((Range<Int>, String) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.theme = theme
        self.rows = rows
        self.showsHourLabels = showsHourLabels
        self.time = time
        self.blockSize = blockSize
        self.brush = brush
        self.isAdding = isAdding
        self.selection = selection
        self.selectedLayer = selectedLayer
        self.onDrag = onDrag
        self.onDeselect = onDeselect
        self.onClear = onClear
        self.onResize = onResize
        self.onMove = onMove
        self.onSelectLayer = onSelectLayer
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
                width: blockSize.map {
                    GridLayout.width(side: $0, labelWidth: labelWidth, blocksPerGroup: snapshot.grid.blocksPerGroup)
                        + 2 * margin
                },
                height: blockSize.map {
                    GridLayout.height(
                        side: $0, rows: resolvedRows, rowsAfterGaps: rowsAfterGaps, hasHeader: hasMinuteLabels)
                        + 2 * margin
                })
            .overlay {
                if onDrag != nil {
                    GeometryReader { proxy in
                        let layout = layout(size: proxy.size)
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(paintGesture(size: proxy.size))
                            .contextMenu {
                                if let onClear, let pointed, let target = snapshot.clearable(
                                    at: pointed, selection: selection, selectedLayer: selectedLayer, card: pointedLayer) {
                                    Button("Clear Blocks", systemImage: "eraser") { onClear(target.range, target.layer) }
                                }
                            }
                            .onContinuousHover { phase in
                                if case .active(let point) = phase {
                                    hovered = layout.index(at: point, count: snapshot.cells.count, clamped: false)
                                    hoveredLayer = hovered.flatMap { layer(at: point, in: $0, layout: layout) }
                                    pointed = hovered
                                    pointedLayer = hoveredLayer
                                    isOverHandle = handle(at: point, layout: layout) != nil
                                } else {
                                    hovered = nil
                                    hoveredLayer = nil
                                    isOverHandle = false
                                }
                            }
                        if let range = labeled {
                            BlockInfo(
                                snapshot: snapshot, theme: theme, range: range, layer: labeledLayer,
                                brush: resizing != nil || moving != nil ? resizableCategory.map(Brush.category) : brush)
                                .fixedSize()
                                .position(infoPosition(for: range, layout: layout, size: proxy.size))
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            #if canImport(AppKit)
            .onChange(of: cursor) { old, new in
                if old != nil { NSCursor.pop() }
                new?.push()
            }
            #endif
    }

    #if canImport(AppKit)
    /// Resize arrows over a knob and while dragging one; an open hand over a selection that can be moved, closed while
    /// moving it; and the add pointer over the blocks while adding.
    private var cursor: NSCursor? {
        if moving != nil { return .closedHand }
        if resizing != nil || isOverHandle { return .resizeLeftRight }
        if isAdding, hovered != nil || drag != nil { return .dragCopy }
        if let hovered, isMovable, selection?.contains(hovered) == true { return .openHand }
        return nil
    }
    #endif

    private var dragged: Range<Int>? {
        drag.map { min($0.start, $0.end)..<(max($0.start, $0.end) + 1) }
    }

    /// What the pointer is over: with a brush, the one block it would paint; over a card of a stack, the run of its
    /// activity (the selection when that's what's selected); otherwise the whole selection when over it, or what a
    /// click would pick out (see `DaySnapshot.target`).
    private var hoveredTarget: (range: Range<Int>, layer: String?)? {
        guard let hovered, !isOverHandle else { return nil }
        if brush != nil { return (hovered..<(hovered + 1), nil) }
        if let hoveredLayer {
            if let selection, selection.contains(hovered), selectedLayer == hoveredLayer { return (selection, hoveredLayer) }
            return snapshot.target(at: hovered, card: hoveredLayer)
        }
        if let selection, selection.contains(hovered) { return (selection, selectedLayer) }
        return snapshot.target(at: hovered)
    }

    private var hoveredRange: Range<Int>? { hoveredTarget?.range }

    /// Blocks the label describes: the drag in progress, else what the pointer is over, else the selection.
    private var labeled: Range<Int>? {
        resizing?.range ?? moved ?? dragged ?? hoveredRange ?? selection
    }

    /// The one activity the label describes, when it's about one card of a stack.
    private var labeledLayer: String? {
        if resizing != nil || moving != nil { return selectedLayer }
        if dragged != nil { return nil }
        if let hoveredTarget { return hoveredTarget.layer }
        return selectedLayer
    }

    /// The card of block `index` under `point`, by activity, with its stack spread apart as it is under the pointer.
    /// Nil over a block holding one activity or none, and while painting.
    private func layer(at point: CGPoint, in index: Int, layout: GridLayout) -> String? {
        guard brush == nil, snapshot.cells.indices.contains(index) else { return nil }
        let shown = snapshot.cells[index].layers.suffix(3)
        guard shown.count > 1 else { return nil }
        let cards = Self.cards(in: layout.frame(index), count: shown.count, spread: true)
        for (card, layer) in zip(cards, shown).reversed() where card.insetBy(dx: -1, dy: -1).contains(point) {
            return layer.categoryID
        }
        return shown.last?.categoryID
    }

    /// Where each drawn layer of a block goes, bottom first: cards of one size, the top one at the bottom-right and each
    /// under it a step up and to the left. Spread apart, as under the pointer, they step further and reach a little
    /// past the block, so each is easy to click.
    static func cards(in rect: CGRect, count: Int, spread: Bool) -> [CGRect] {
        guard count > 1 else { return [rect] }
        let step = rect.width * 0.26 / CGFloat(count - 1)
        let size = rect.width - step * CGFloat(count - 1)
        let stride = spread ? step * 1.7 : step
        let span = size + stride * CGFloat(count - 1)
        let left = rect.midX - span / 2
        let top = rect.midY - span / 2
        return (0..<count).map { level in
            let along = stride * CGFloat(level)
            return CGRect(x: left + along, y: top + along, width: size, height: size)
        }
    }

    /// Whether dragging inside the selection moves it: it holds something logged, and there's no brush.
    private var isMovable: Bool {
        guard onMove != nil, brush == nil, let selection else { return false }
        return snapshot.isLogged(anyOf: selection)
    }

    /// The blocks an edit being dragged is put on: the brush's drag (or the block under it), or where a dragged end
    /// or a moved selection would put the selection.
    private var edited: Range<Int>? {
        if let range = resizing?.range ?? moved { return range }
        guard brush != nil else { return nil }
        return dragged ?? hovered.map { $0..<($0 + 1) }
    }

    /// What each block an edit being dragged would change ends up holding: its activities, or none once it's emptied.
    private var preview: [Int: [BlockCell.Layer]] {
        var preview: [Int: [BlockCell.Layer]] = [:]
        if let moving, let moved, let selection, selectedLayer == nil {
            for index in selection { preview[index] = [] }
            for index in moved where snapshot.cells.indices.contains(index - moving.offset) {
                preview[index] = snapshot.cells[index - moving.offset].layers
            }
        } else if let moving, let moved, let selection, let layer = selectedLayer {
            // Only that activity moves, onto what the blocks it lands on hold.
            for index in selection { preview[index] = snapshot.cells[index].layers.filter { $0.categoryID != layer } }
            for index in moved where snapshot.cells.indices.contains(index) {
                let others = (preview[index] ?? snapshot.cells[index].layers).filter { $0.categoryID != layer }
                let source = index - moving.offset
                let carried = snapshot.cells.indices.contains(source) ? snapshot.cells[source].layer(layer) : nil
                preview[index] = others + (carried.map { [$0] } ?? [])
            }
        } else if let resizing, let selection, let category = resizableCategory, selectedLayer != nil {
            for index in selection { preview[index] = snapshot.cells[index].layers.filter { $0.categoryID != category } }
            for index in resizing.range where snapshot.cells.indices.contains(index) {
                let others = (preview[index] ?? snapshot.cells[index].layers).filter { $0.categoryID != category }
                preview[index] = others + [snapshot.cells[selection.lowerBound].layer(category) ?? BlockCell.Layer(categoryID: category)]
            }
        } else if let resizing, let selection, let category = resizableCategory {
            for index in selection { preview[index] = [] }
            for index in resizing.range { preview[index] = [BlockCell.Layer(categoryID: category)] }
        } else if case .layer(let id) = brush, let edited {
            // Added, or taken off when every block holds it already.
            let cells = edited.filter(snapshot.cells.indices.contains).map { snapshot.cells[$0] }
            let isHeld = cells.allSatisfy { $0.categoryIDs.contains(id) }
            for cell in cells {
                preview[cell.index] = cell.layers.filter { $0.categoryID != id } + (isHeld ? [] : [BlockCell.Layer(categoryID: id)])
            }
        } else if let brush, let edited {
            for index in edited { preview[index] = brush.categoryID.map { [BlockCell.Layer(categoryID: $0)] } ?? [] }
        }
        return preview.filter { snapshot.cells.indices.contains($0.key) }
    }

    /// Where the selection being moved would land.
    private var moved: Range<Int>? {
        guard let moving, let selection else { return nil }
        return selection.lowerBound + moving.offset..<selection.upperBound + moving.offset
    }

    /// The activity the selection holds throughout, when it's logged as that alone, so its ends can be dragged.
    private var resizableCategory: String? {
        guard onResize != nil, brush == nil, let selection, snapshot.cells.indices.contains(selection.lowerBound),
              snapshot.cells.indices.contains(selection.upperBound - 1)
        else { return nil }
        if let selectedLayer {
            return snapshot.cells[selection].allSatisfy({ $0.layer(selectedLayer) != nil }) ? selectedLayer : nil
        }
        guard let category = snapshot.cells[selection.lowerBound].categoryID,
              snapshot.cells[selection].allSatisfy({ $0.categoryIDs == [category] })
        else { return nil }
        return category
    }

    /// The blocks with handles: the selection, or what it's being dragged to. None while it's being moved.
    private var handled: Range<Int>? {
        guard moving == nil else { return nil }
        return resizing?.range ?? (resizableCategory != nil ? selection : nil)
    }

    /// The middle of the knob on each end of `range`: on the top-left corner of its first block and the bottom-right
    /// corner of its last, like the ends of selected text that runs over several lines. Where the activity is a card of
    /// a stack, on that card's corners.
    private func handlePoints(of range: Range<Int>, layout: GridLayout) -> (start: CGPoint, end: CGPoint) {
        let first = frame(of: resizableCategory, at: range.lowerBound, layout: layout)
        let last = frame(of: resizableCategory, at: range.upperBound - 1, layout: layout)
        let inset = layout.radius * 0.3
        return (
            CGPoint(x: first.minX + inset, y: first.minY + inset),
            CGPoint(x: last.maxX - inset, y: last.maxY - inset))
    }

    /// Where `layer`'s card in block `index` is drawn, as the block shows it now (an edit being dragged included), or
    /// the whole block when it isn't in a stack.
    private func frame(of layer: String?, at index: Int, layout: GridLayout) -> CGRect {
        let rect = layout.frame(index)
        guard let layer, snapshot.cells.indices.contains(index) else { return rect }
        let cell = preview[index].map(snapshot.cells[index].holding) ?? snapshot.cells[index]
        let shown = cell.layers.suffix(3)
        guard shown.count > 1, let level = shown.firstIndex(where: { $0.categoryID == layer }) else { return rect }
        let cards = Self.cards(in: rect, count: shown.count, spread: isSpread(index, depth: shown.count))
        return cards[level - shown.startIndex]
    }

    /// Whether block `index`'s stack of `depth` cards is spread apart: under the pointer, and while one of its cards is
    /// the selection, so each can be clicked, its ends dragged included. Not while painting or moving.
    private func isSpread(_ index: Int, depth: Int) -> Bool {
        guard depth > 1, brush == nil, onDrag != nil, moving == nil else { return false }
        if let resizing { return selectedLayer != nil && resizing.range.contains(index) }
        return index == hovered || (selectedLayer != nil && selection?.contains(index) == true)
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
    private var hasMinuteLabels: Bool { showsHourLabels && !snapshot.grid.labeledMinutes.isEmpty }
    private var rowsAfterGaps: Set<Int> {
        snapshot.grid.rowsAfterGaps(schedule: snapshot.status.schedule, rowCount: Self.rowCount(for: snapshot))
    }
    /// Room around a fixed-size grid for what reaches past the blocks, like the current block's ring.
    private var margin: CGFloat { blockSize.map { $0 * 0.4 } ?? 0 }

    private func layout(size: CGSize) -> GridLayout {
        GridLayout(
            size: size, rows: resolvedRows, offset: snapshot.status.schedule.gridOffset, labelWidth: labelWidth,
            blocksPerGroup: snapshot.grid.blocksPerGroup, rowsAfterGaps: rowsAfterGaps, hasHeader: hasMinuteLabels,
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
                // So does a press inside a selection that can be moved: it moves it.
                if resizing == nil, moving == nil, isMovable, let drag, drag.start == drag.end,
                   hypot(value.translation.width, value.translation.height) >= 3, selection?.contains(drag.start) == true {
                    moving = (drag.start, 0)
                    self.drag = nil
                }
                if let moving, let selection {
                    // It stops at either end of the day.
                    guard let index = layout.index(at: value.location, count: count, clamped: true) else { return }
                    let offset = min(max(index - moving.from, -selection.lowerBound), count - selection.upperBound)
                    self.moving = (moving.from, offset)
                    return
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
            .onEnded { value in
                defer { drag = nil }
                if let moving {
                    self.moving = nil
                    if let selection, moving.offset != 0 { onMove?(selection, moving.offset) }
                    return
                }
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
                    } else if let card = layer(at: value.startLocation, in: index, layout: layout(size: size)) {
                        // A card of a stack: its activity's run, or nothing when that's what was selected.
                        let target = snapshot.target(at: index, card: card)
                        if selection == target.range, selectedLayer == target.layer { onDeselect?() } else { select(target) }
                    } else if let selection, selection.contains(index) {
                        onDeselect?()
                    } else {
                        select(snapshot.target(at: index))
                    }
                } else if dragged == selection {
                    onDeselect?()
                } else {
                    onDrag?(dragged)
                }
            }
    }

    /// Selects what a click picked out: one activity of the blocks, or everything they hold.
    private func select(_ target: (range: Range<Int>, layer: String?)) {
        if let layer = target.layer, let onSelectLayer {
            onSelectLayer(target.range, layer)
        } else {
            onDrag?(target.range)
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
        let preview = preview
        let edited = edited

        if showsHourLabels {
            let fontSize = min(11, max(7, side * 0.8))
            for row in rows {
                let first = row * perRow - offset
                let text = Text(String(format: "%02d", schedule.hour(ofRow: row)))
                    .font(.system(size: fontSize, weight: .medium, design: mood >= .uneasy ? .monospaced : .rounded))
                    .foregroundColor(first >= awake ? theme.accent : theme.secondaryText)
                let y = grid.y(ofRow: row) + side / 2
                context.draw(text, at: CGPoint(x: originX - 6, y: y), anchor: .trailing)
            }
            // Over the column each starts.
            for minute in snapshot.grid.labeledMinutes {
                let column = minute / Schedule.blockMinutes
                let text = Text(String(format: "%02d", minute))
                    .font(.system(size: fontSize, weight: .medium, design: mood >= .uneasy ? .monospaced : .rounded))
                    .foregroundColor(theme.secondaryText)
                let x = grid.x(ofColumn: column) + side / 2
                context.draw(text, at: CGPoint(x: x, y: originY - grid.headerHeight / 2))
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

            // A block an edit is being dragged over shows what it would end up as.
            let shown = preview[cell.index].map(cell.holding) ?? cell
            // Several activities at once are stacked as cards (see `cards`), three at most drawn.
            // They spread apart under the pointer, and while one of them is the selection, so each can be clicked.
            let depth = min(shown.layers.count, 3)
            let isSpread = isSpread(cell.index, depth: depth)
            let stack = shown.layers.isEmpty
                ? [shown] : (shown.layers.count - depth + 1...shown.layers.count).map { shown.holding(Array(shown.layers.prefix($0))) }
            let cards = Self.cards(in: rect, count: stack.count, spread: isSpread)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let cardRadius = min(radius, (cards.first?.width ?? side) * 0.3)
            /// The outline of the card holding `layer`, or of the whole block.
            let outline = { (layer: String?) -> Path in
                guard let layer, depth > 1, let level = stack.firstIndex(where: { $0.categoryID == layer }) else { return path }
                return Path(roundedRect: cards[level], cornerRadius: cardRadius).rotated(by: angle, around: center)
            }
            for (level, layer) in stack.enumerated() {
                let card = cards[level]
                let cardPath = Path(roundedRect: card, cornerRadius: depth > 1 ? cardRadius : radius).rotated(by: angle, around: center)
                if level > 0 {
                    // A sliver of the grid between a card and the ones under it, so two of one color still read as two.
                    var knockout = context
                    knockout.blendMode = .clear
                    let edge = max(1, side * 0.07)
                    knockout.fill(
                        Path(roundedRect: CGRect(x: card.minX - edge, y: card.minY - edge, width: card.width + edge, height: card.height + edge),
                             cornerRadius: cardRadius)
                            .rotated(by: angle, around: center),
                        with: .color(.black))
                }
                switch theme.paint(for: layer, categories: snapshot.categories) {
                case .solid(let color):
                    if mood == .nightmare && cell.phase == .past && noise(cell.index, 5) < 0.1 {
                        // Dead block: only the outline is left.
                        context.stroke(cardPath, with: .color(color.opacity(0.6)), lineWidth: max(1, side * 0.08))
                    } else {
                        context.fill(cardPath, with: .color(color))
                    }
                case .planned(let color, let dashed):
                    let line = max(1, side * 0.1)
                    context.fill(cardPath, with: .color(color.opacity(0.18)))
                    context.stroke(
                        Path(roundedRect: card.insetBy(dx: line / 2, dy: line / 2), cornerRadius: depth > 1 ? cardRadius : radius)
                            .rotated(by: angle, around: center),
                        with: .color(color.opacity(0.9)),
                        style: StrokeStyle(lineWidth: line, dash: dashed ? [line * 1.6, line * 1.2] : []))
                case .empty(let color):
                    context.fill(cardPath, with: .color(color))
                }
            }

            if onDrag != nil {
                // While an edit is dragged, the blocks it's put on are outlined, showing what they'd end up as. A
                // selection, or a drag making one, is washed over as well.
                let line = max(1.5, side * 0.12)
                // With one activity of a stack picked out, it's that card that's outlined.
                if let edited {
                    if edited.contains(cell.index) {
                        context.stroke(outline(brush == nil ? selectedLayer : nil), with: .color(theme.text), lineWidth: line)
                    }
                } else if let dragged, dragged.contains(cell.index) {
                    context.fill(path, with: .color(theme.text.opacity(0.2)))
                    context.stroke(path, with: .color(theme.text), lineWidth: line)
                } else if dragged == nil, selection?.contains(cell.index) == true {
                    let target = outline(selectedLayer)
                    context.fill(target, with: .color(theme.text.opacity(0.2)))
                    context.stroke(target, with: .color(theme.text), lineWidth: line)
                } else if brush == nil, drag == nil, let hoveredTarget, hoveredTarget.range.contains(cell.index) {
                    // The stretch of one category (or one gap) under the pointer.
                    context.stroke(outline(hoveredTarget.layer), with: .color(theme.text.opacity(0.75)), lineWidth: line)
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
            let top = grid.y(ofRow: boundaryRow) - grid.gap(beforeRow: boundaryRow) / 2
            let bottom = grid.y(ofRow: boundaryRow) + side + grid.gap(beforeRow: boundaryRow + 1) / 2
            let x = grid.x(ofColumn: column) - grid.gap(beforeColumn: column) / 2
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
    /// The one activity of a stack it's about, if it's about one.
    let layer: String?
    let brush: Brush?

    var body: some View {
        let schedule = snapshot.status.schedule
        let cells = snapshot.cells[range.clamped(to: snapshot.cells.indices)]
        // Named when every block holds the same thing; about one activity, the blocks as they'd be holding just that.
        let shared = layer.map { layer in
            cells.first.map { $0.holding($0.layer(layer).map { [$0] } ?? [BlockCell.Layer(categoryID: layer)]) }
        } ?? cells.first.flatMap { first in cells.allSatisfy { $0.categoryIDs == first.categoryIDs } ? first : nil }
        let notes = Set(cells.map { cell in layer.map { cell.layer($0)?.note } ?? cell.note })
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
            if shared != nil, notes.count == 1, let note = notes.first ?? nil {
                // The label is drawn at its natural size, so a long note is shortened here.
                Text(note.count > 40 ? note.prefix(39) + "…" : note)
                    .italic()
                    .foregroundStyle(theme.text)
            }
            if case .layer = brush {
                Image(systemName: "plus").foregroundStyle(theme.secondaryText)
                if let category = brush?.categoryID.flatMap({ snapshot.categories[$0] }) {
                    Label(category.name, systemImage: category.symbol).foregroundStyle(theme.color(of: category))
                }
            } else if let brush, shared?.categoryIDs != (brush.categoryID.map { [$0] } ?? []) {
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

    /// What a block holds: its activities, bottom first, or else what kind of empty it is.
    @ViewBuilder private func content(of cell: BlockCell) -> some View {
        if !cell.layers.isEmpty {
            let categories = cell.categoryIDs.compactMap { snapshot.categories[$0] }
            ForEach(Array(categories.enumerated()), id: \.offset) { position, category in
                if position > 0 {
                    Text("+").foregroundStyle(theme.secondaryText)
                }
                let isLast = position == categories.count - 1
                Label(cell.phase == .future && isLast ? "\(category.name) (planned)" : category.name, systemImage: category.symbol)
                    .foregroundStyle(theme.color(of: category))
            }
        } else if cell.isOvertime {
            Text("Past bedtime").foregroundStyle(theme.accent)
        } else {
            Text(cell.phase == .future ? cell.isWindDown ? "Wind down" : "Nothing planned" : "Unlogged")
                .foregroundStyle(theme.secondaryText)
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
    /// Room above the blocks for the minute labels.
    let headerHeight: CGFloat
    let gap: CGFloat
    let radius: CGFloat
    let gridWidth: CGFloat
    let originX: CGFloat
    let originY: CGFloat

    /// Blocks between the wider gaps, or nil for none.
    let blocksPerGroup: Int?
    /// Rows with a wider gap above them, counted from the first row of the day.
    let rowsAfterGaps: Set<Int>

    static let gapRatio: CGFloat = 0.24
    /// How much wider the gaps between groups of blocks are.
    static let groupGapRatio: CGFloat = 0.3
    /// The minute labels' room is a block high, up to this, as their text stops growing.
    static let maxHeaderHeight: CGFloat = 16

    /// Grid width for blocks of `side` points.
    static func width(side: CGFloat, labelWidth: CGFloat, blocksPerGroup: Int?) -> CGFloat {
        labelWidth + side * blocksWide(blocksPerGroup)
    }

    /// How many blocks wide a row is, its gaps included.
    private static func blocksWide(_ blocksPerGroup: Int?) -> CGFloat {
        let columns = CGFloat(Schedule.blocksPerHour)
        let groupGaps = blocksPerGroup.map { CGFloat((Schedule.blocksPerHour - 1) / $0) } ?? 0
        return columns + (columns - 1) * gapRatio + groupGaps * groupGapRatio
    }

    static func height(side: CGFloat, rows: Range<Int>, rowsAfterGaps: Set<Int>, hasHeader: Bool) -> CGFloat {
        (hasHeader ? min(side, maxHeaderHeight) : 0) + side * blocksHigh(rows: rows, rowsAfterGaps: rowsAfterGaps)
    }

    /// How many blocks high `rows` are, their gaps included.
    private static func blocksHigh(rows: Range<Int>, rowsAfterGaps: Set<Int>) -> CGFloat {
        let count = CGFloat(max(1, rows.count))
        let groupGaps = CGFloat(rowsAfterGaps.filter { $0 > rows.lowerBound && rows.contains($0) }.count)
        return count + (count - 1) * gapRatio + groupGaps * groupGapRatio
    }

    init(
        size: CGSize, rows: Range<Int>, offset: Int, labelWidth: CGFloat, blocksPerGroup: Int?,
        rowsAfterGaps: Set<Int>, hasHeader: Bool, margin: CGFloat = 0
    ) {
        let gapRatio = Self.gapRatio
        let blocksWide = Self.blocksWide(blocksPerGroup)
        self.rows = rows
        self.offset = offset
        self.blocksPerGroup = blocksPerGroup
        self.rowsAfterGaps = rowsAfterGaps
        let available = CGSize(width: size.width - 2 * margin, height: size.height - 2 * margin)
        // A block high header counts as one more row, until it stops growing.
        let rowsHigh = Self.blocksHigh(rows: rows, rowsAfterGaps: rowsAfterGaps)
        var tallest = available.height / (rowsHigh + (hasHeader ? 1 : 0))
        if hasHeader, tallest > Self.maxHeaderHeight {
            tallest = (available.height - Self.maxHeaderHeight) / rowsHigh
        }
        side = min((available.width - labelWidth) / blocksWide, tallest)
        headerHeight = hasHeader ? min(side, Self.maxHeaderHeight) : 0
        gap = side * gapRatio
        radius = side * 0.28
        gridWidth = side * blocksWide
        originX = margin + labelWidth + (available.width - labelWidth - gridWidth) / 2
        originY = margin + headerHeight
    }

    func frame(_ index: Int) -> CGRect {
        let slot = index + offset
        return CGRect(
            x: x(ofColumn: slot % Schedule.blocksPerHour), y: y(ofRow: slot / Schedule.blocksPerHour),
            width: side, height: side)
    }

    /// The top edge of the blocks in `row`, counted from the first row of the day.
    func y(ofRow row: Int) -> CGFloat {
        let groupGaps = rowsAfterGaps.filter { $0 > rows.lowerBound && $0 <= row }.count
        return originY + CGFloat(row - rows.lowerBound) * (side + gap) + CGFloat(groupGaps) * side * Self.groupGapRatio
    }

    /// The gap above `row`: wider when the settings put one there.
    func gap(beforeRow row: Int) -> CGFloat {
        row > rows.lowerBound && rowsAfterGaps.contains(row) ? gap + side * Self.groupGapRatio : gap
    }

    /// The left edge of the blocks in `column`.
    func x(ofColumn column: Int) -> CGFloat {
        let groupGaps = blocksPerGroup.map { column / $0 } ?? 0
        return originX + CGFloat(column) * (side + gap) + CGFloat(groupGaps) * side * Self.groupGapRatio
    }

    /// The gap to the left of `column`: wider when it starts a group.
    func gap(beforeColumn column: Int) -> CGFloat {
        guard let blocksPerGroup, column > 0, column % blocksPerGroup == 0 else { return gap }
        return gap + side * Self.groupGapRatio
    }

    /// The block under `point`, out of `count`. Unclamped, points off the blocks give nil;
    /// clamped, they give the nearest block, so a drag can run past the grid's edge.
    func index(at point: CGPoint, count: Int, clamped: Bool) -> Int? {
        let columns = Schedule.blocksPerHour
        // Each block reaches halfway across the gaps on either side of it.
        let column = point.x < originX - gap / 2
            ? -1 : (0..<columns).first { point.x < x(ofColumn: $0) + side + gap(beforeColumn: $0 + 1) / 2 } ?? columns
        let row = point.y < originY - gap / 2
            ? -1
            : rows.first { point.y < y(ofRow: $0) + side + gap(beforeRow: $0 + 1) / 2 }.map { $0 - rows.lowerBound }
                ?? rows.count
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
