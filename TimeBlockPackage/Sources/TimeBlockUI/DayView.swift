import SwiftUI
import TimeBlockKit

/// Lets the day view log blocks: select blocks, then open the activities with the + beside them and click one. A
/// selection stays until you click off the blocks, so its activity can be changed again. With the Add tool picked, or
/// ⌘ held, an activity is added to what the blocks hold instead, or comes off where they all hold it; the Add tool goes
/// back to Normal once it has. Clicking one card of blocks holding several activities selects just that activity
/// (`layer`), and what's done to the selection is done to it alone. Selected blocks that are logged can be given a note
/// or dragged somewhere else, and a selection of one activity can be dragged longer or shorter by its ends. Delete
/// clears a selection.
///
/// Each edit is given the activity it's limited to, or nil for everything the blocks hold.
public struct DayEditor {
    /// Whether activities replace what blocks hold or are added to it.
    public var tool: Binding<Tool>
    public var selection: Binding<Range<Int>?>
    /// The one activity of the selection picked out, or nil for all it holds.
    public var layer: Binding<String?>
    /// Logs a range as an activity alone, or clears it.
    public var paint: (Range<Int>, Brush, String?) -> Void
    /// Writes a note on the logged blocks of a range, or takes it off with nil.
    public var annotate: ((Range<Int>, String?, String?) -> Void)?
    /// Stars or unstars a category.
    public var toggleFavorite: ((String) -> Void)?
    /// Moves the ends of a run of one activity: logs the blocks it takes in and clears the ones it lets go.
    public var resize: ((Range<Int>, Range<Int>, String?) -> Void)?
    /// Moves what a range holds some blocks along, clearing the blocks it leaves.
    public var move: ((Range<Int>, Int, String?) -> Void)?
    /// Adds a category to what a range holds, or takes it off when every block holds it. Without it there's
    /// no adding.
    public var toggle: ((Range<Int>, String) -> Void)?

    public init(
        tool: Binding<Tool> = .constant(.normal), selection: Binding<Range<Int>?>, layer: Binding<String?> = .constant(nil),
        paint: @escaping (Range<Int>, Brush, String?) -> Void, toggle: ((Range<Int>, String) -> Void)? = nil,
        annotate: ((Range<Int>, String?, String?) -> Void)? = nil, toggleFavorite: ((String) -> Void)? = nil,
        resize: ((Range<Int>, Range<Int>, String?) -> Void)? = nil, move: ((Range<Int>, Int, String?) -> Void)? = nil
    ) {
        self.tool = tool
        self.selection = selection
        self.layer = layer
        self.paint = paint
        self.toggle = toggle
        self.annotate = annotate
        self.toggleFavorite = toggleFavorite
        self.resize = resize
        self.move = move
    }

    /// The activity an edit of `range` is limited to: the one picked out, when `range` is the selection.
    private func layer(for range: Range<Int>) -> String? {
        range == selection.wrappedValue ? layer.wrappedValue : nil
    }

    /// The grid picked out `range`: select it.
    func dragged(_ range: Range<Int>) {
        select(range)
    }

    /// One card of a stack was clicked: select its activity's run, that activity alone.
    func selectLayer(_ range: Range<Int>, _ categoryID: String) {
        select(range, layer: categoryID)
    }

    /// A chip was clicked: log the selection with it, keeping it selected. With one activity picked out, it's that one
    /// that's replaced, and the new one is picked out in its place.
    func chose(_ choice: Brush) {
        guard let range = selection.wrappedValue else { return }
        let picked = layer(for: range)
        paint(range, choice, picked)
        if picked != nil { layer.wrappedValue = choice.categoryID }
    }

    /// A chip was clicked while adding: add it to the selection's activities or take it off.
    func toggled(_ categoryID: String) {
        guard let range = selection.wrappedValue else { return }
        toggle?(range, categoryID)
        // The activity picked out is held throughout, so it was just taken off.
        if layer.wrappedValue == categoryID { layer.wrappedValue = nil }
        // Adding is one go: the Add tool goes back to Normal once it has added (or taken off).
        if tool.wrappedValue == .add { tool.wrappedValue = .normal }
    }

    func deselect() {
        select(nil)
    }

    /// Clear was picked from the grid's right-click menu: empty `range`, or take `picked` off it, keeping a selection as
    /// it was.
    func clear(_ range: Range<Int>, layer picked: String?) {
        paint(range, .clear, picked)
        if picked != nil, picked == layer(for: range) { layer.wrappedValue = nil }
    }

    /// Delete was pressed: empty the selection, or take the activity picked out of it off, keeping it selected.
    func clearSelection() {
        if let range = selection.wrappedValue { clear(range, layer: layer(for: range)) }
    }

    /// An end of the selection was dragged: move the run's end there, and select it as it is now.
    func resized(_ range: Range<Int>, to newRange: Range<Int>) {
        resize?(range, newRange, layer(for: range))
        selection.wrappedValue = newRange
    }

    /// The selection was dragged `offset` blocks along: move what it holds there, and select it there.
    func moved(_ range: Range<Int>, by offset: Int) {
        move?(range, offset, layer(for: range))
        selection.wrappedValue = range.lowerBound + offset..<range.upperBound + offset
    }

    /// Writes a note on the logged blocks of `range`, on the activity picked out when it's the selection.
    func annotated(_ range: Range<Int>, _ note: String?) {
        annotate?(range, note, layer(for: range))
    }

    private func select(_ range: Range<Int>?, layer categoryID: String? = nil) {
        selection.wrappedValue = range
        layer.wrappedValue = categoryID
    }
}

/// The window's own controls, each put where it belongs in the day and drawn in its theme: the day shown at the top,
/// the view over the stats it counts, starting a timer beside what's on now, and the window's own (keep on top,
/// settings) in the top corner.
public struct DayControls {
    /// Goes back and forth between days, at the top left.
    public var day: ((MoodTheme) -> AnyView)?
    /// Switches between views of the day (Activity, Body…), over the stats.
    public var track: ((MoodTheme) -> AnyView)?
    /// Starts a timer, beside what's on now.
    public var timer: ((MoodTheme) -> AnyView)?
    /// The window's own, at the top right.
    public var corner: ((MoodTheme) -> AnyView)?

    public init(
        day: ((MoodTheme) -> AnyView)? = nil, track: ((MoodTheme) -> AnyView)? = nil,
        timer: ((MoodTheme) -> AnyView)? = nil, corner: ((MoodTheme) -> AnyView)? = nil
    ) {
        self.day = day
        self.track = track
        self.timer = timer
        self.corner = corner
    }
}

/// The main app's day screen. Unlike widgets, it animates.
public struct DayView: View {
    let snapshot: DaySnapshot
    var time: Double
    /// Without one the day is read-only.
    var editor: DayEditor?
    /// Today's timers; without them there are none to start.
    var timers: TimerControls?
    /// The moment shown, which timers count to.
    var date: Date
    /// Just the counter, the blocks and the timers going, small, for a window kept over other apps.
    var isCompact: Bool
    var controls: DayControls
    @Environment(\.colorScheme) private var colorScheme
    /// The grid takes the keyboard when blocks are selected, for Delete, and Return to open the activities.
    @FocusState private var isGridFocused: Bool
    /// Whether the activities are open for the selected blocks.
    @State private var showsActivities = false

    public init(
        snapshot: DaySnapshot, time: Double = 0, editor: DayEditor? = nil, timers: TimerControls? = nil,
        date: Date = .now, isCompact: Bool = false, controls: DayControls = DayControls()
    ) {
        self.snapshot = snapshot
        self.time = time
        self.editor = editor
        self.timers = timers
        self.date = date
        self.isCompact = isCompact
        self.controls = controls
    }

    private var clockLabel: String {
        let minute = snapshot.status.nowMinute % (24 * 60)
        return String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    /// The day shown, when it isn't today.
    private var otherDate: Date? {
        snapshot.status.isOver || snapshot.status.isAhead ? snapshot.day.flatMap { DayID.date($0) } : nil
    }

    /// The top line: the day shown and, today, the time; the window's own controls at the end.
    private func topLine(theme: MoodTheme) -> some View {
        HStack(spacing: 6) {
            if let day = controls.day {
                day(theme)
                if otherDate == nil {
                    Text(clockLabel)
                }
            } else {
                let when = otherDate.map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) }
                Label("\(snapshot.track.name) · \(when ?? clockLabel)", systemImage: snapshot.track.symbol)
            }
            Spacer(minLength: 8)
            controls.corner?(theme)
        }
        .font(.system(size: 13, weight: .medium, design: .monospaced))
        .foregroundStyle(theme.secondaryText)
    }

    /// Where today's counter would be, another day's share of blocks logged, or planned.
    private func otherDayHeader(theme: MoodTheme) -> some View {
        let awake = snapshot.status.schedule.awakeBlocks
        let logged = snapshot.cells.prefix(awake).filter { $0.categoryID != nil }.count
        return VStack(alignment: .leading, spacing: 0) {
            Text("\(awake > 0 ? logged * 100 / awake : 0)%")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundStyle(theme.text)
            Text(snapshot.status.isAhead ? "planned" : "logged")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
        }
    }

    public var body: some View {
        let theme = MoodTheme(mood: snapshot.mood, colorScheme: colorScheme)
        if isCompact {
            compactBody(theme: theme)
        } else {
            fullBody(theme: theme)
        }
    }

    private func fullBody(theme: MoodTheme) -> some View {
        let status = snapshot.status
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                topLine(theme: theme)
                HStack(alignment: .bottom) {
                    if otherDate != nil {
                        otherDayHeader(theme: theme)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            CounterView(
                                value: status.blocksLeft, theme: theme, size: 64,
                                total: status.schedule.awakeBlocks, time: time)
                            Text(MoodCopy.caption(snapshot.mood))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        if let track = controls.track {
                            track(theme)
                                .padding(.bottom, 3)
                        }
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
            }
            if let line = MoodCopy.line(snapshot.mood) {
                Text(line)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.accent)
            }
            grid(theme: theme, blockSize: 20)
            if !status.isOver && !status.isAhead {
                HStack {
                    NowChip(snapshot: snapshot, theme: theme)
                    Spacer(minLength: 8)
                    controls.timer?(theme)
                }
                timerList(theme: theme)
            }
            StoryBar(snapshot: snapshot, theme: theme)
            Legend(snapshot: snapshot, theme: theme, limit: 4, fontSize: 11)
        }
        .padding(22)
        // Extra space goes below the day rather than into bigger blocks.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .modifier(DayFrame(editor: editor, theme: theme, time: time))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// The counter on one line, then the blocks smaller: the day at a glance, beside other work.
    private func compactBody(theme: MoodTheme) -> some View {
        let status = snapshot.status
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let date = otherDate {
                    Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.text)
                } else {
                    CounterView(value: status.blocksLeft, theme: theme, size: 26, total: status.schedule.awakeBlocks, time: time)
                    Label(clockLabel, systemImage: snapshot.track.symbol)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer(minLength: 8)
                controls.corner?(theme)
            }
            grid(theme: theme, blockSize: 15)
            if !status.isOver && !status.isAhead {
                timerList(theme: theme)
            }
        }
        .padding(12)
        .modifier(DayFrame(editor: editor, theme: theme, time: time))
    }

    @ViewBuilder
    private func timerList(theme: MoodTheme) -> some View {
        if let timers, !timers.timers.isEmpty {
            TimerList(controls: timers, categories: snapshot.categories, theme: theme, date: date)
                // Clicks around the buttons shouldn't drop the selection.
                .contentShape(Rectangle())
                .onTapGesture {}
        }
    }

    private func grid(theme: MoodTheme, blockSize: CGFloat) -> some View {
        BlockGridView(
            snapshot: snapshot, theme: theme, time: time, blockSize: blockSize,
            selection: editor?.selection.wrappedValue, selectedLayer: editor?.layer.wrappedValue,
            onDrag: editor.map { editor in { editor.dragged($0) } },
            onDeselect: editor?.deselect, onClear: editor.map { editor in { editor.clear($0, layer: $1) } },
            onResize: editor.flatMap { editor in editor.resize.map { _ in { editor.resized($0, to: $1) } } },
            onMove: editor.flatMap { editor in editor.move.map { _ in { editor.moved($0, by: $1) } } },
            onSelectLayer: editor.map { editor in { editor.selectLayer($0, $1) } },
            selectionAccessory: editor.map { editor in AnyView(activitiesButton(editor, theme: theme)) })
            .frame(maxWidth: .infinity)
            .focusable(editor != nil, interactions: .edit)
            .focusEffectDisabled()
            .focused($isGridFocused)
            .onDeleteCommand { editor?.clearSelection() }
            .onKeyPress(.return) {
                guard editor?.selection.wrappedValue != nil else { return .ignored }
                showsActivities = true
                return .handled
            }
            .onChange(of: editor?.selection.wrappedValue) { _, range in
                if range != nil { isGridFocused = true } else { showsActivities = false }
            }
    }

    /// The button beside the selection's label, which opens the activities for it: a + for empty blocks, the edit
    /// symbol (a pencil on a square) for ones with something logged.
    private func activitiesButton(_ editor: DayEditor, theme: MoodTheme) -> some View {
        let isLogged = editor.selection.wrappedValue.map(snapshot.isLogged(anyOf:)) ?? false
        return Button {
            showsActivities.toggle()
        } label: {
            Image(systemName: isLogged ? "square.and.pencil" : "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(theme.backgroundBottom)
                .frame(width: 22, height: 22)
                .background(Circle().fill(theme.text))
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isLogged ? "Edit the selected blocks (Return)" : "Log the selected blocks (Return)")
        .popover(isPresented: $showsActivities, arrowEdge: .trailing) {
            activities(editor, theme: theme)
                .padding(14)
                .frame(width: 430)
        }
    }

    /// What the selected blocks can be logged as: the tools, the activities, the note, and the times selected.
    private func activities(_ editor: DayEditor, theme: MoodTheme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ToolPicker(tool: editor.tool.wrappedValue, theme: theme) { editor.tool.wrappedValue = $0 }
                Spacer()
                if let hint = hint(for: editor) {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryText)
                }
            }
            CategoryPalette(
                categories: snapshot.trackCategories, favorites: snapshot.favorites,
                selected: paletteChoice(editor), theme: theme, choose: editor.chose,
                toggle: editor.toggle.map { _ in editor.toggled }, isAdding: editor.tool.wrappedValue == .add,
                toggleFavorite: editor.toggleFavorite)
            if let range = editor.selection.wrappedValue, editor.annotate != nil {
                noteField(for: range, layer: editor.layer.wrappedValue, annotate: editor.annotated, theme: theme)
            }
        }
    }

    /// The chips to show as picked: the activity picked out, or else the categories every selected block holds.
    private func paletteChoice(_ editor: DayEditor) -> Set<Brush> {
        guard let range = editor.selection.wrappedValue else { return [] }
        if let layer = editor.layer.wrappedValue { return [.category(layer)] }
        let cells = snapshot.cells[range.clamped(to: snapshot.cells.indices)]
        guard let first = cells.first else { return [] }
        let shared = cells.dropFirst().reduce(Set(first.categoryIDs)) { $0.intersection($1.categoryIDs) }
        return Set(shared.map(Brush.category))
    }

    /// Edits the note of the selected blocks that are logged, or of the activity picked out of them; there is none to
    /// edit while none are.
    @ViewBuilder private func noteField(
        for range: Range<Int>, layer: String?, annotate: @escaping (Range<Int>, String?) -> Void, theme: MoodTheme
    ) -> some View {
        let logged = snapshot.cells[range.clamped(to: snapshot.cells.indices)].compactMap { cell in
            layer.map { cell.layer($0) } ?? cell.layers.last
        }
        if !logged.isEmpty {
            let notes = Set(logged.map(\.note))
            NoteField(
                note: notes.count == 1 ? notes.first ?? nil : nil, isMixed: notes.count > 1, theme: theme
            ) { annotate(range, $0) }
                // A new selection starts a new edit.
                .id("\(range)\(layer ?? "")")
        }
    }

    /// The times selected, and the activity picked out of them: "08:00–08:30 Lunch".
    private func hint(for editor: DayEditor) -> String? {
        guard let range = editor.selection.wrappedValue else { return nil }
        let schedule = snapshot.status.schedule
        let clock = { (minute: Int) in String(format: "%02d:%02d", minute / 60, minute % 60) }
        let times = "\(clock(schedule.clockMinute(ofBlock: range.lowerBound)))–\(clock(schedule.clockMinute(ofBlock: range.upperBound)))"
        let name = editor.layer.wrappedValue.flatMap { snapshot.categories[$0] }.map { " \($0.name)" } ?? ""
        return "\(times)\(name)"
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

/// What the whole day, full or compact, does around its blocks.
private struct DayFrame: ViewModifier {
    let editor: DayEditor?
    let theme: MoodTheme
    let time: Double

    func body(content: Content) -> some View {
        content
            // The grid's label can reach across the whole day, not just the grid.
            .coordinateSpace(BlockGridView.labelSpace)
            // A click anywhere off the blocks drops the selection.
            .contentShape(Rectangle())
            .onTapGesture { editor?.deselect() }
            .background(MoodBackground(theme: theme, time: time))
    }
}
