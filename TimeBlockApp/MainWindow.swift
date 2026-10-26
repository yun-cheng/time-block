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
    /// Whether the window has room for the settings beside the day, which follows them showing once it has widened or
    /// narrowed; and whether it's doing that, when its width is the window's to change.
    @State private var hasSettingsRoom = false
    @State private var isResizing = false
    /// Whether the offer to undo the last change shows, and whether the pointer is on it, which keeps it.
    @State private var showsUndoToast = false
    @State private var isUndoToastHovered = false
    @State private var undoToastHiding: Task<Void, Never>?
    /// How big the compact day is, for the window kept on top to fit.
    @State private var compactSize: CGSize?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if model.isPinned {
                // No toolbar or settings: just the day, and the window fits it; the timer dialog fits in it.
                day
                    .fixedSize()
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { compactSize = $0 }
                    // Over the day, which the window keeps fitting.
                    .overlay {
                        if showsTimerStarter {
                            TimerDialog(model: model, theme: theme, isCompact: true, isOpen: $showsTimerStarter)
                        }
                    }
            } else {
                // The settings are always beside the day, past the window's edge while they're hidden: showing or
                // hiding them only widens or narrows the window, and nothing else moves.
                HStack(spacing: 0) {
                    dayColumn
                    HStack(spacing: 0) {
                        Divider()
                        SettingsView(model: model)
                    }
                    .frame(width: Self.settingsWidth)
                }
                // As wide as the day, and the settings when there's room for them, which the window keeps to; only its
                // height changes. While the window widens or narrows, as wide as it is.
                .frame(width: isResizing ? nil : dayWidth + (hasSettingsRoom ? Self.settingsWidth : 0), alignment: .leading)
                .frame(minWidth: dayWidth, maxWidth: dayWidth + Self.settingsWidth, alignment: .leading)
                .clipped()
                .frame(minHeight: 600)
            }
        }
        .background(
            WindowPin(isPinned: model.isPinned, compactSize: compactSize, width: windowWidth, isResizing: isResizing) {
                hasSettingsRoom = model.showsSettings
                isResizing = false
            })
        .onAppear { hasSettingsRoom = model.showsSettings }
        .onChange(of: model.showsSettings) { isResizing = true }
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
        .onChange(of: model.lastChange) {
            withAnimation(.snappy) { showsUndoToast = true }
            hideUndoToast(after: .seconds(5))
        }
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
                isCompact: model.isPinned, controls: controls)
        }
    }

    /// The day in its scroll view, with what shows over it.
    private var dayColumn: some View {
        GeometryReader { window in
            // The app's scroll bar drawn in SwiftUI, like the settings'.
            AppScrollView(lane: 10) {
                day
                    // Fill the window, but scroll when it is too short for the whole day.
                    .frame(minHeight: window.size.height - 20)
                    .padding(10)
            }
        }
        .overlay(alignment: .bottom) {
            if showsUndoToast {
                UndoToast(
                    undo: undoTitles.undo, redo: undoTitles.redo, wasUndo: model.lastChange?.kind == .undone,
                    perform: { $0 ? redo() : undo() }
                )
                .onHover { isHovered in
                    isUndoToastHovered = isHovered
                    if !isHovered { hideUndoToast(after: .seconds(2)) }
                }
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if showsTimerStarter {
                TimerDialog(model: model, theme: theme, isOpen: $showsTimerStarter)
            }
        }
        .frame(width: dayWidth)
    }

    /// The whole day's width, around its padding in the window.
    private var dayWidth: CGFloat { DayView.width(of: model.snapshot) + 20 }

    private static let settingsWidth: CGFloat = 320

    /// The window's width: the day's, and the settings' beside it when there's room for them, or once it's widening
    /// or narrowing, when they show. It changes only with that, so the window's resized only in the animation.
    private var windowWidth: CGFloat {
        dayWidth + ((isResizing ? model.showsSettings : hasSettingsRoom) ? Self.settingsWidth : 0)
    }

    /// The window's buttons, each where it belongs in the day.
    private var controls: DayControls {
        DayControls(
            day: { AnyView(DayPicker(model: model, theme: $0)) },
            track: { AnyView(TrackSwitch(track: $model.settings.track, theme: $0)) },
            timer: { AnyView(StartTimerButton(theme: $0, isOpen: $showsTimerStarter)) },
            corner: { theme in
                AnyView(
                    HStack(spacing: 0) {
                        pinButton
                        // Settings need the whole window.
                        if !model.isPinned {
                            Button {
                                model.showsSettings.toggle()
                            } label: {
                                Label("Settings", systemImage: "gearshape")
                            }
                            .buttonStyle(DayButtonStyle(theme: theme, isOn: model.showsSettings))
                            .help(model.showsSettings ? "Hide Settings" : "Show Settings")
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(DayButtonStyle(theme: theme))
                    .padding(.trailing, -6))
            })
    }

    private func undo() {
        if undoManager?.canUndo == true { undoManager?.undo() }
        updateUndoTitles()
    }

    private func redo() {
        if undoManager?.canRedo == true { undoManager?.redo() }
        updateUndoTitles()
    }

    /// Hides the offer to undo after `delay`, unless something newer or the pointer keeps it.
    private func hideUndoToast(after delay: Duration) {
        undoToastHiding?.cancel()
        undoToastHiding = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, !isUndoToastHovered else { return }
            withAnimation(.snappy) { showsUndoToast = false }
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
/// and gives it back its old height after. Unpinned, it keeps the window as wide as the day and the settings showing,
/// widening or narrowing it in an animation as they show or hide.
private struct WindowPin: NSViewRepresentable {
    let isPinned: Bool
    let compactSize: CGSize?
    /// The whole day's window width, which it keeps to: wider with the settings showing, narrower again without.
    let width: CGFloat
    /// Whether to widen or narrow it to `width` in an animation, rather than at once.
    let isResizing: Bool
    /// Called once the animation is over.
    let resized: @MainActor () -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        // Before the window takes the new layout, so the size it had is still there to keep.
        if let window = view.window {
            apply(context.coordinator, to: window)
        } else {
            DispatchQueue.main.async {
                if let window = view.window { apply(context.coordinator, to: window) }
            }
        }
    }

    private func apply(_ coordinator: Coordinator, to window: NSWindow) {
        coordinator.apply(
            isPinned, compactSize: compactSize, width: width, isResizing: isResizing, resized: resized, to: window)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        private var wasPinned: Bool?
        /// The whole day's window height, to go back to.
        private var fullHeight: CGFloat?
        /// The width the window is being animated to.
        private var animatingTo: CGFloat?

        func apply(
            _ isPinned: Bool, compactSize: CGSize?, width: CGFloat, isResizing: Bool,
            resized: @escaping @MainActor () -> Void, to window: NSWindow
        ) {
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
                fullHeight = window.frame.height
            }
            let wasPinned = wasPinned
            self.wasPinned = isPinned
            // Once the new layout is in, keeping the window's top left corner where it is.
            DispatchQueue.main.async { [fullHeight] in
                if isPinned, let compactSize {
                    // The title bar sits over the content, so it's added to the day's height.
                    let titleBar = window.frame.height - window.contentLayoutRect.height
                    Self.resize(window, to: NSSize(width: compactSize.width, height: compactSize.height + titleBar))
                } else if !isPinned {
                    // Back from compact, it takes its old height too; pinned since launch, the window's first.
                    let height = wasPinned == true ? fullHeight ?? 720 : window.frame.height
                    let size = NSSize(width: width, height: height)
                    if isResizing {
                        self.animate(window, to: size, then: resized)
                    } else {
                        Self.resize(window, to: size)
                    }
                }
            }
        }

        /// Widens or narrows the window to `size`, then calls `done`, unless it's sent somewhere else meanwhile.
        private func animate(_ window: NSWindow, to size: NSSize, then done: @escaping @MainActor () -> Void) {
            guard animatingTo != size.width else { return }
            let frame = Self.frame(of: window, sized: size)
            guard frame.size != window.frame.size else {
                done()
                return
            }
            animatingTo = size.width
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.animatingTo == size.width else { return }
                    self.animatingTo = nil
                    done()
                }
            }
        }

        private static func resize(_ window: NSWindow, to size: NSSize) {
            let frame = frame(of: window, sized: size)
            guard window.frame.size != frame.size else { return }
            window.setFrame(frame, display: true)
        }

        /// The window's frame at `size`, rounded up, its top left corner where it is, on its screen.
        private static func frame(of window: NSWindow, sized size: NSSize) -> NSRect {
            let size = NSSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
            let frame = NSRect(x: window.frame.minX, y: window.frame.maxY - size.height, width: size.width, height: size.height)
            return window.constrainFrameRect(frame, to: window.screen)
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
