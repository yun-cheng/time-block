import SwiftUI
import TimeBlockKit

/// Lets the day view log blocks, either way round: select blocks, then click a category; or pick a
/// category as a brush, then drag across blocks. A selection stays until you click off the blocks, so
/// its category can be changed again; a brush is put down after one drag, so the next click can't
/// log by accident. With the Add tool picked, or ⌘ held, a category is added to what the blocks hold instead, or
/// comes off where they all hold it. Selected blocks that are logged can be given a note or dragged somewhere else, and
/// a selection of one activity can be dragged longer or shorter by its ends. Delete clears a selection.
public struct DayEditor {
    public var brush: Binding<Brush?>
    /// Whether categories replace what blocks hold or are added to it.
    public var tool: Binding<Tool>
    public var selection: Binding<Range<Int>?>
    public var paint: (Range<Int>, Brush) -> Void
    /// Writes a note on the logged blocks of a range, or takes it off with nil.
    public var annotate: ((Range<Int>, String?) -> Void)?
    /// Stars or unstars a category.
    public var toggleFavorite: ((String) -> Void)?
    /// Moves the ends of a run of one activity: logs the blocks it takes in and clears the ones it lets go.
    public var resize: ((Range<Int>, Range<Int>) -> Void)?
    /// Moves what a range holds some blocks along, clearing the blocks it leaves.
    public var move: ((Range<Int>, Int) -> Void)?
    /// Adds a category to what a range holds, or takes it off when every block holds it. Without it there's
    /// no adding.
    public var toggle: ((Range<Int>, String) -> Void)?

    public init(
        brush: Binding<Brush?>, tool: Binding<Tool> = .constant(.normal), selection: Binding<Range<Int>?>,
        paint: @escaping (Range<Int>, Brush) -> Void, toggle: ((Range<Int>, String) -> Void)? = nil,
        annotate: ((Range<Int>, String?) -> Void)? = nil, toggleFavorite: ((String) -> Void)? = nil,
        resize: ((Range<Int>, Range<Int>) -> Void)? = nil, move: ((Range<Int>, Int) -> Void)? = nil
    ) {
        self.brush = brush
        self.tool = tool
        self.selection = selection
        self.paint = paint
        self.toggle = toggle
        self.annotate = annotate
        self.toggleFavorite = toggleFavorite
        self.resize = resize
        self.move = move
    }

    /// Whether categories are added to what blocks hold: with the Add tool, or while ⌘ is held.
    func isAdding(isCommandDown: Bool) -> Bool {
        toggle != nil && (tool.wrappedValue == .add || isCommandDown)
    }

    /// What dragging across the grid does now: the brush picked up, adding instead while adding.
    func activeBrush(isCommandDown: Bool) -> Brush? {
        isAdding(isCommandDown: isCommandDown) ? brush.wrappedValue?.layered : brush.wrappedValue
    }

    /// The grid picked out `range`: log it with `brush`, the one picked up as it is now, or else select it.
    func dragged(_ range: Range<Int>, with brush: Brush?) {
        if let brush {
            log(range, brush)
        } else {
            selection.wrappedValue = range
        }
    }

    /// A chip was clicked: log the selection with it (keeping it selected), or else pick it up as the
    /// brush (or put it down).
    func chose(_ choice: Brush) {
        if let range = selection.wrappedValue {
            paint(range, choice)
        } else {
            brush.wrappedValue = brush.wrappedValue == choice ? nil : choice
        }
    }

    /// A chip was clicked while adding: add it to the selection's activities or take it off, or else pick it up as a
    /// brush that does that (or put it down).
    func toggled(_ categoryID: String) {
        if let range = selection.wrappedValue {
            toggle?(range, categoryID)
        } else {
            let choice = Brush.layer(categoryID)
            brush.wrappedValue = brush.wrappedValue == choice ? nil : choice
        }
    }

    func deselect() {
        selection.wrappedValue = nil
    }

    /// Clear was picked from the grid's right-click menu: empty `range`, keeping a selection as it was.
    func clear(_ range: Range<Int>) {
        paint(range, .clear)
    }

    /// Delete was pressed: empty the selection, keeping it selected.
    func clearSelection() {
        if let range = selection.wrappedValue { clear(range) }
    }

    /// An end of the selection was dragged: move the run's end there, and select it as it is now.
    func resized(_ range: Range<Int>, to newRange: Range<Int>) {
        resize?(range, newRange)
        selection.wrappedValue = newRange
    }

    /// The selection was dragged `offset` blocks along: move what it holds there, and select it there.
    func moved(_ range: Range<Int>, by offset: Int) {
        move?(range, offset)
        selection.wrappedValue = range.lowerBound + offset..<range.upperBound + offset
    }

    private func log(_ range: Range<Int>, _ choice: Brush) {
        if case .layer(let id) = choice {
            toggle?(range, id)
        } else {
            paint(range, choice)
        }
        brush.wrappedValue = nil
        selection.wrappedValue = nil
    }
}

/// The main app's day screen. Unlike widgets, it animates.
public struct DayView: View {
    let snapshot: DaySnapshot
    var time: Double
    /// Without one the day is read-only.
    var editor: DayEditor?
    @Environment(\.colorScheme) private var colorScheme
    /// The grid takes the keyboard when blocks are selected, for Delete.
    @FocusState private var isGridFocused: Bool
    /// Holding ⌘ adds, as the Add tool does.
    @State private var isCommandDown = false

    public init(snapshot: DaySnapshot, time: Double = 0, editor: DayEditor? = nil) {
        self.snapshot = snapshot
        self.time = time
        self.editor = editor
    }

    private var clockLabel: String {
        let minute = snapshot.status.nowMinute % (24 * 60)
        return String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    /// The day shown, when it isn't today.
    private var otherDate: Date? {
        snapshot.status.isOver || snapshot.status.isAhead ? snapshot.day.flatMap { DayID.date($0) } : nil
    }

    /// Another day's date where today's counter would be, and how much of it was logged, or is planned.
    private func otherDayHeader(_ date: Date, theme: MoodTheme) -> some View {
        let awake = snapshot.status.schedule.awakeBlocks
        let logged = snapshot.cells.prefix(awake).filter { $0.categoryID != nil }.count
        return VStack(alignment: .leading, spacing: 0) {
            Label(
                "\(snapshot.track.name) · \(date.formatted(.dateTime.weekday(.wide)))", systemImage: snapshot.track.symbol)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.secondaryText)
            Text(date.formatted(.dateTime.day().month(.abbreviated)))
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundStyle(theme.text)
            Text("\(awake > 0 ? logged * 100 / awake : 0)% \(snapshot.status.isAhead ? "planned" : "logged")")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
        }
    }

    public var body: some View {
        let theme = MoodTheme(mood: snapshot.mood, colorScheme: colorScheme)
        let status = snapshot.status
        let brush = editor?.activeBrush(isCommandDown: isCommandDown)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                if let date = otherDate {
                    otherDayHeader(date, theme: theme)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Label("\(snapshot.track.name) · \(clockLabel)", systemImage: snapshot.track.symbol)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.secondaryText)
                        CounterView(value: status.blocksLeft, theme: theme, size: 64, total: status.schedule.awakeBlocks, time: time)
                        Text(MoodCopy.caption(snapshot.mood))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    stat("\(status.schedule.awakeBlocks)", "usable", theme)
                    if !status.isOver && !status.isAhead {
                        stat("\(status.blocksUsed)", "used", theme)
                    }
                    if !status.isAhead {
                        stat("\(snapshot.loggedCount)", "logged", theme)
                    }
                    if let longestSit = snapshot.longestSit {
                        stat(durationText(blocks: longestSit), "longest sit", theme)
                    }
                    if status.overtimeBlocks > 0 {
                        stat("\(status.overtimeBlocks)", "over", theme, color: theme.accent)
                    }
                }
            }
            if let line = MoodCopy.line(snapshot.mood) {
                Text(line)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.accent)
            }
            BlockGridView(
                snapshot: snapshot, theme: theme, time: time, blockSize: 20, brush: brush,
                isAdding: editor?.isAdding(isCommandDown: isCommandDown) ?? false,
                selection: editor?.selection.wrappedValue, onDrag: editor.map { editor in { editor.dragged($0, with: brush) } },
                onDeselect: editor?.deselect, onClear: editor.map { editor in { editor.clear($0) } },
                onResize: editor.flatMap { editor in editor.resize.map { _ in { editor.resized($0, to: $1) } } },
                onMove: editor.flatMap { editor in editor.move.map { _ in { editor.moved($0, by: $1) } } })
                .frame(maxWidth: .infinity)
                .focusable(editor != nil, interactions: .edit)
                .focusEffectDisabled()
                .focused($isGridFocused)
                .onDeleteCommand { editor?.clearSelection() }
                .onChange(of: editor?.selection.wrappedValue) { _, range in
                    if range != nil { isGridFocused = true }
                }
            if !status.isOver && !status.isAhead {
                NowChip(snapshot: snapshot, theme: theme)
            }
            StoryBar(snapshot: snapshot, theme: theme)
            Legend(snapshot: snapshot, theme: theme, limit: 4, fontSize: 11)
            if let editor {
                Divider().overlay(theme.secondaryText.opacity(0.3))
                ToolPicker(tool: editor.tool.wrappedValue, theme: theme) { editor.tool.wrappedValue = $0 }
                CategoryPalette(
                    categories: snapshot.trackCategories, favorites: snapshot.favorites,
                    selected: paletteChoice(editor), theme: theme, choose: editor.chose,
                    toggle: editor.toggle.map { _ in editor.toggled }, isAdding: editor.tool.wrappedValue == .add,
                    toggleFavorite: editor.toggleFavorite)
                    // Clicks between the chips shouldn't drop the selection.
                    .contentShape(Rectangle())
                    .onTapGesture {}
                if let range = editor.selection.wrappedValue, let annotate = editor.annotate {
                    noteField(for: range, annotate: annotate, theme: theme)
                }
                if let hint = hint(for: editor) {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryText)
                }
            }
        }
        .padding(22)
        // Extra space goes below the day rather than into bigger blocks.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // A click anywhere off the blocks and chips drops the selection.
        .contentShape(Rectangle())
        .onTapGesture { editor?.deselect() }
        .background(MoodBackground(theme: theme, time: time))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .tracksCommandKey($isCommandDown)
    }

    /// The chips to show as picked: the categories every selected block holds, or else the brush.
    private func paletteChoice(_ editor: DayEditor) -> Set<Brush> {
        guard let range = editor.selection.wrappedValue else { return Set([editor.brush.wrappedValue].compactMap { $0 }) }
        let cells = snapshot.cells[range.clamped(to: snapshot.cells.indices)]
        guard let first = cells.first else { return [] }
        let shared = cells.dropFirst().reduce(Set(first.categoryIDs)) { $0.intersection($1.categoryIDs) }
        return Set(shared.map(Brush.category))
    }

    /// Edits the note of the selected blocks that are logged; there is none to edit while none are.
    @ViewBuilder private func noteField(
        for range: Range<Int>, annotate: @escaping (Range<Int>, String?) -> Void, theme: MoodTheme
    ) -> some View {
        let logged = snapshot.cells[range.clamped(to: snapshot.cells.indices)].filter { $0.categoryID != nil }
        if !logged.isEmpty {
            let notes = Set(logged.map(\.note))
            NoteField(
                note: notes.count == 1 ? notes.first ?? nil : nil, isMixed: notes.count > 1, theme: theme
            ) { annotate(range, $0) }
                // A new selection starts a new edit.
                .id(range)
        }
    }

    /// What's selected, or what dragging will do with a brush picked up; nil when neither.
    private func hint(for editor: DayEditor) -> String? {
        if let range = editor.selection.wrappedValue {
            let schedule = snapshot.status.schedule
            let clock = { (minute: Int) in String(format: "%02d:%02d", minute / 60, minute % 60) }
            return "\(clock(schedule.clockMinute(ofBlock: range.lowerBound)))–\(clock(schedule.clockMinute(ofBlock: range.upperBound))) selected"
        }
        guard let brush = editor.activeBrush(isCommandDown: isCommandDown) else { return nil }
        guard let name = brush.categoryID.flatMap({ snapshot.categories[$0] })?.name else {
            return "Drag across blocks to clear them"
        }
        if case .layer = brush { return "Drag across blocks to add \(name)" }
        return "Drag across blocks to log \(name)"
    }

    private func stat(_ value: String, _ label: String, _ theme: MoodTheme, color: Color? = nil) -> some View {
        HStack(spacing: 4) {
            Text(value).font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundStyle(color ?? theme.text)
            Text(label).font(.system(size: 12)).foregroundStyle(theme.secondaryText)
        }
    }
}

/// A one-line note for the selected blocks. It is saved on Return, when the field loses focus, and when the
/// selection changes or goes away.
private struct NoteField: View {
    let note: String?
    /// The blocks hold different notes; typing one replaces them all.
    let isMixed: Bool
    let theme: MoodTheme
    let save: (String?) -> Void
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(note: String?, isMixed: Bool, theme: MoodTheme, save: @escaping (String?) -> Void) {
        self.note = note
        self.isMixed = isMixed
        self.theme = theme
        self.save = save
        _text = State(initialValue: note ?? "")
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.bubble")
                .foregroundStyle(theme.secondaryText)
            TextField(isMixed ? "Several notes" : "Add a note", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(commit)
        }
        .font(.system(size: 12))
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
        .onDisappear(perform: commit)
        // Clicks here shouldn't drop the selection.
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Leaving a mixed field empty keeps the notes it had.
        guard trimmed != (note ?? ""), !(isMixed && trimmed.isEmpty) else { return }
        save(trimmed.isEmpty ? nil : trimmed)
    }
}
