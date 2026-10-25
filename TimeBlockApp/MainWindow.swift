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

    var body: some View {
        GeometryReader { window in
            // The app's scroll bar drawn in SwiftUI: AppKit's would sit under the inspector, showing through it.
            AppScrollView(lane: 10) {
                // 15 fps is plenty for the pulse and horror effects, and keeps an open window cheap.
                TimelineView(.animation(minimumInterval: 1.0 / 15)) { context in
                    DayView(
                        snapshot: model.snapshot(at: context.date),
                        time: context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000),
                        editor: DayEditor(
                            brush: $model.brush, selection: $model.selection,
                            paint: { model.set($0, to: $1.categoryID) },
                            annotate: { model.setNote($1, for: $0) }, toggleFavorite: model.toggleFavorite,
                            resize: { model.resize($0, to: $1) }, move: { model.move($0, by: $1) }))
                }
                // Fill the window, but scroll when it is too short for the whole day.
                .frame(minHeight: window.size.height - 20)
                .padding(10)
            }
        }
        .frame(minWidth: 400, minHeight: 600)
        .toolbar {
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
                    model.showsSettings.toggle()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help(model.showsSettings ? "Hide Settings" : "Show Settings")
            }
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
        .inspector(isPresented: $model.showsSettings) {
            SettingsView(model: model)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
                // With nothing of its own in the toolbar, the panel would take the day's buttons over it.
                .toolbar { Spacer() }
        }
    }
}

extension MainWindow {
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
