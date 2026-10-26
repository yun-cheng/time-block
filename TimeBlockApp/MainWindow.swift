import Combine
import SwiftUI
import TimeBlockKit
import TimeBlockUI

struct MainWindow: View {
    @Bindable var model: AppModel
    @Environment(\.undoManager) private var undoManager
    /// What Undo and Redo would do now ("Undo Move Blocks"), nil when there's nothing to. Undo managers can't be
    /// observed, so this follows their notifications.
    @State private var undoTitles = UndoTitles()
    /// Whether a menu is open, such as the grid's right-click menu. The day stops animating meanwhile: every frame
    /// would build the menu again, and its icons would flash.
    @State private var isMenuOpen = false
    @State private var showsTimerStarter = false
    /// How big the compact day is, for the window kept on top to fit.
    @State private var compactSize: CGSize?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if model.isPinned {
                // No toolbar or settings: just the day, and the window fits it.
                day
                    .fixedSize()
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { compactSize = $0 }
            } else {
                GeometryReader { window in
                    // The app's scroll bar drawn in SwiftUI: AppKit's would sit under the inspector, showing through it.
                    AppScrollView(lane: 10) {
                        day
                            // Fill the window, but scroll when it is too short for the whole day.
                            .frame(minHeight: window.size.height - 20)
                            .padding(10)
                    }
                }
                .overlay {
                    if showsTimerStarter {
                        TimerDialog(model: model, theme: theme, isOpen: $showsTimerStarter)
                    }
                }
                .frame(minWidth: 400, minHeight: 600)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        DayPicker(model: model)
                    }
                    ToolbarItem(placement: .principal) {
                        TrackPicker(track: $model.settings.track)
                    }
                    ToolbarItemGroup {
                        Button {
                            if undoManager?.canUndo == true { undoManager?.undo() }
                            updateUndoTitles()
                        } label: {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                        }
                        .help(undoTitles.undo ?? "Undo")
                        .disabled(undoTitles.undo == nil)
                        Button {
                            if undoManager?.canRedo == true { undoManager?.redo() }
                            updateUndoTitles()
                        } label: {
                            Label("Redo", systemImage: "arrow.uturn.forward")
                        }
                        .help(undoTitles.redo ?? "Redo")
                        .disabled(undoTitles.redo == nil)
                    }
                    ToolbarItem {
                        Button {
                            showsTimerStarter.toggle()
                        } label: {
                            Label("Start Timer", systemImage: "stopwatch")
                        }
                        .help("Start a timer that logs an activity as it goes")
                    }
                    ToolbarItem {
                        pinButton
                    }
                    ToolbarItem {
                        Button {
                            model.showsSettings.toggle()
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                        .help(model.showsSettings ? "Hide Settings" : "Show Settings")
                    }
                }
                .inspector(isPresented: $model.showsSettings) {
                    SettingsView(model: model)
                        .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
                        // With nothing of its own in the toolbar, the panel would take the day's buttons over it.
                        .toolbar { Spacer() }
                }
            }
        }
        .background(WindowPin(isPinned: model.isPinned, compactSize: compactSize))
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            isMenuOpen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            isMenuOpen = false
        }
        .onAppear {
            model.undoManager = undoManager
            updateUndoTitles()
        }
        .onChange(of: undoManager) {
            model.undoManager = undoManager
            updateUndoTitles()
        }
        // Edits, undos and redos post these; the model clearing its edits changes the day it's showing.
        .onReceive(undoNotifications) { _ in updateUndoTitles() }
        .onChange(of: model.dayLog) { updateUndoTitles() }
        .onChange(of: model.otherLog) { updateUndoTitles() }
    }
}

extension MainWindow {
    private var day: some View {
        // 15 fps is plenty for the pulse and horror effects, and keeps an open window cheap.
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: isMenuOpen)) { context in
            DayView(
                snapshot: model.shownSnapshot(at: context.date),
                time: context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000),
                editor: DayEditor(
                    tool: $model.tool, selection: $model.selection, layer: $model.selectedLayer,
                    paint: { model.set($0, to: $1.categoryID, layer: $2) }, toggle: { model.toggle($0, $1) },
                    annotate: { model.setNote($1, for: $0, layer: $2) }, toggleFavorite: model.toggleFavorite,
                    resize: { model.resize($0, to: $1, layer: $2) }, move: { model.move($0, by: $1, layer: $2) }),
                timers: model.timerControls, date: context.date,
                isCompact: model.isPinned, compactAccessory: AnyView(pinButton.buttonStyle(.borderless)))
        }
    }

    /// Keeps the window over other apps', compact, or brings the whole day back.
    private var pinButton: some View {
        Button {
            model.isPinned.toggle()
        } label: {
            Label(model.isPinned ? "Unpin" : "Keep on Top", systemImage: model.isPinned ? "pin.slash" : "pin")
        }
        .labelStyle(.iconOnly)
        .help(model.isPinned ? "Show the whole day, behind other windows again" : "Keep a compact day on top of other windows")
    }

    private var theme: MoodTheme {
        MoodTheme(mood: model.snapshot.mood, colorScheme: colorScheme)
    }

    private struct UndoTitles: Equatable {
        var undo: String?
        var redo: String?
    }

    private var undoNotifications: some Publisher<Notification, Never> {
        let center = NotificationCenter.default
        return Publishers.Merge3(
            center.publisher(for: .NSUndoManagerDidCloseUndoGroup, object: undoManager),
            center.publisher(for: .NSUndoManagerDidUndoChange, object: undoManager),
            center.publisher(for: .NSUndoManagerDidRedoChange, object: undoManager))
    }

    private func updateUndoTitles() {
        guard let undoManager else {
            undoTitles = UndoTitles()
            return
        }
        undoTitles = UndoTitles(
            undo: undoManager.canUndo ? undoManager.undoMenuItemTitle : nil,
            redo: undoManager.canRedo ? undoManager.redoMenuItemTitle : nil)
    }
}

/// Goes back and forth between days: the previous and next day, today, and the day shown, which picks one from a
/// calendar.
struct DayPicker: View {
    @Bindable var model: AppModel
    @State private var showsCalendar = false

    /// Side by side, as in Calendar: ‹ Today › and the date.
    var body: some View {
        HStack(spacing: 6) {
            ControlGroup {
                Button {
                    model.showDay(-1)
                } label: {
                    Label("Previous Day", systemImage: "chevron.left")
                }
                .help("Previous Day")
                Button("Today") { model.showToday() }
                    .help("Go to Today")
                    .disabled(model.isShowingToday)
                Button {
                    model.showDay(1)
                } label: {
                    Label("Next Day", systemImage: "chevron.right")
                }
                .help("Next Day")
            }
            .fixedSize()
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
        }
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

/// Go ▸ Previous Day (⌘[), Next Day (⌘]), Today (⌘T).
struct DayCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Go") {
            Button("Previous Day") { model.showDay(-1) }
                .keyboardShortcut("[", modifiers: .command)
            Button("Next Day") { model.showDay(1) }
                .keyboardShortcut("]", modifiers: .command)
            Button("Today") { model.showToday() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(model.isShowingToday)
        }
    }
}

/// Window ▸ Keep on Top (⌥⌘P).
struct PinCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Toggle("Keep on Top", isOn: $model.isPinned)
                .keyboardShortcut("p", modifiers: [.command, .option])
        }
    }
}

/// Floats the window over other apps' windows, on every Space, while the day is pinned, fitted to the compact day,
/// and gives it back its old size after.
private struct WindowPin: NSViewRepresentable {
    let isPinned: Bool
    let compactSize: CGSize?

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        // Before the window takes the new layout, so the size it had is still there to keep.
        if let window = view.window {
            context.coordinator.apply(isPinned, compactSize: compactSize, to: window)
        } else {
            DispatchQueue.main.async { [isPinned, compactSize] in
                if let window = view.window { context.coordinator.apply(isPinned, compactSize: compactSize, to: window) }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        private var wasPinned: Bool?
        /// The whole day's window size, to go back to.
        private var fullSize: NSSize?

        func apply(_ isPinned: Bool, compactSize: CGSize?, to window: NSWindow) {
            // A full-screen window has its own Space, with nothing to float over.
            if isPinned, window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
            window.level = isPinned ? .floating : .normal
            if isPinned {
                window.collectionBehavior.insert(.canJoinAllSpaces)
            } else {
                window.collectionBehavior.remove(.canJoinAllSpaces)
            }
            if isPinned, wasPinned == false {
                fullSize = window.frame.size
            }
            let wasPinned = wasPinned
            self.wasPinned = isPinned
            // Once the new layout is in, keeping the window's top left corner where it is.
            DispatchQueue.main.async { [fullSize] in
                if isPinned, let compactSize {
                    // The title bar sits over the content, so it's added to the day's height.
                    let titleBar = window.frame.height - window.contentLayoutRect.height
                    Self.resize(window, to: NSSize(width: compactSize.width, height: compactSize.height + titleBar))
                } else if !isPinned, wasPinned == true {
                    // Pinned since launch, it goes back to the window's first size.
                    Self.resize(window, to: fullSize ?? NSSize(width: 480, height: 720))
                }
            }
        }

        private static func resize(_ window: NSWindow, to size: NSSize) {
            let size = NSSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
            guard window.frame.size != size else { return }
            let frame = NSRect(x: window.frame.minX, y: window.frame.maxY - size.height, width: size.width, height: size.height)
            window.setFrame(window.constrainFrameRect(frame, to: window.screen), display: true)
        }
    }
}

/// Switches between views of the day: Activity, Body, …
struct TrackPicker: View {
    @Binding var track: Track

    var body: some View {
        Picker("View", selection: $track) {
            ForEach(Track.allCases, id: \.self) { track in
                Label(track.name, systemImage: track.symbol)
                    .accessibilityLabel(track.name)
                    .help(track.name)
                    .tag(track)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

/// View ▸ Activity (⌘1), Body (⌘2), …
struct TrackCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            ForEach(Array(Track.allCases.enumerated()), id: \.element) { number, track in
                Button(track.name) { model.settings.track = track }
                    .keyboardShortcut(KeyEquivalent(Character("\(number + 1)")), modifiers: .command)
            }
            Divider()
        }
    }
}
