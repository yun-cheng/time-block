import Foundation
import Observation
import os
import TimeBlockKit
import TimeBlockUI
import WidgetKit

@MainActor
@Observable
final class AppModel {
    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            let scheduleChanged = settings.schedule(on: dayLog.day) != oldValue.schedule(on: dayLog.day)
            // Block indexes count from wake time, so a selection would point at other times.
            if scheduleChanged { selection = nil }
            loadDayIfNeeded()
            // A shift that's there already is over, so changing the schedule later doesn't start it again.
            settings.endSleepShiftIfDone(on: dayLog.day)
            SettingsStore.save(settings)
            // Templates are clock times: moving the wake time moves their blocks too.
            if settings.templates != oldValue.templates || scheduleChanged {
                replan()
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Today's logs, in every track.
    private(set) var dayLog: DayLog

    /// Whether the main window shows the settings inspector.
    var showsSettings = false

    /// The brush each view paints with, so switching views keeps your pick. None means just looking.
    var brushes: [Track: Brush] = [:]

    /// Blocks selected in the window, waiting for a category.
    var selection: Range<Int>?

    /// Whether logging the current block from the menu bar also fills the unlogged blocks before it.
    var fillsGap = true

    /// Ticks often enough for the menu bar count to flip on time at each 5-minute boundary.
    private(set) var now = Date()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let store = LogStore.shared
    @ObservationIgnored private let logger = Logger(subsystem: "dev.timeblock.TimeBlock", category: "logs")

    init() {
        var settings = SettingsStore.load()
        let day = settings.dayID(for: .now)
        if settings.endSleepShiftIfDone(on: day) { SettingsStore.save(settings) }
        self.settings = settings
        dayLog = store.load(day: day, wakeMinute: settings.schedule(on: day).wakeMinute)
        planDayIfNeeded()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.now = Date()
                self?.loadDayIfNeeded()
            }
        }
    }

    /// Today's schedule, which a sleep shift moves day by day.
    var schedule: Schedule { settings.schedule(on: dayLog.day) }

    var snapshot: DaySnapshot { snapshot(at: now) }

    func snapshot(at date: Date) -> DaySnapshot {
        settings.snapshot(at: date, log: dayLog)
    }

    var brush: Brush? {
        get { brushes[settings.track] }
        set { brushes[settings.track] = newValue }
    }

    /// The main window's undo manager. Block edits are registered with it, so Edit ▸ Undo takes them back.
    @ObservationIgnored weak var undoManager: UndoManager?

    /// Logs `range` in the current view as a category, or clears it with nil.
    func set(_ range: Range<Int>, to categoryID: String?) {
        edit(categoryID == nil ? "Clear Blocks" : "Log Blocks") {
            $0.set(range, to: categoryID, in: settings.track, schedule: schedule, categories: settings.categories)
        }
    }

    /// Moves the ends of the run of one activity at `range` in the current view to `newRange`.
    func resize(_ range: Range<Int>, to newRange: Range<Int>) {
        edit("Resize Blocks") {
            $0.resize(range, to: newRange, in: settings.track, schedule: schedule, categories: settings.categories)
        }
    }

    /// Moves what `range` holds in the current view `offset` blocks along.
    func move(_ range: Range<Int>, by offset: Int) {
        edit("Move Blocks") {
            $0.move(range, by: offset, in: settings.track, schedule: schedule, categories: settings.categories)
        }
    }

    /// Writes a note on the logged blocks of `range` in the current view, or takes it off with nil.
    func setNote(_ note: String?, for range: Range<Int>) {
        edit(note == nil ? "Remove Note" : "Edit Note") {
            $0.setNote(note, for: range, in: settings.track, schedule: schedule, categories: settings.categories)
        }
    }

    /// What an undo puts back: the day's logs, and the view and selection they were edited in.
    private struct UndoPoint: Sendable {
        let log: DayLog
        let track: Track
        let selection: Range<Int>?
    }

    /// Makes a change to today's logs, which can be undone as `name`.
    private func edit(_ name: String, _ change: (inout DayLog) -> Void) {
        loadDayIfNeeded()
        let before = UndoPoint(log: dayLog, track: settings.track, selection: selection)
        // On a copy: changes read the schedule, which reads `dayLog`.
        var log = dayLog
        change(&log)
        guard log != before.log else { return }
        dayLog = log
        registerUndo(name, restoring: before)
        save()
    }

    private func registerUndo(_ name: String, restoring point: UndoPoint) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { $0.restore(point, name: name) }
        undoManager.setActionName(name)
    }

    /// Puts the logs back as they were, showing the view they changed in, and registers the way back (a redo, after
    /// an undo).
    private func restore(_ point: UndoPoint, name: String) {
        // Undo is cleared when the day rolls over, but not one already under way.
        guard point.log.day == dayLog.day else { return }
        let current = UndoPoint(log: dayLog, track: point.track, selection: settings.track == point.track ? selection : nil)
        dayLog = point.log
        settings.track = point.track
        selection = point.selection
        registerUndo(name, restoring: current)
        save()
    }

    private func save() {
        do {
            try store.save(dayLog)
        } catch {
            logger.error("Couldn't save \(self.dayLog.day): \(error)")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Logs the block in progress, and the unlogged blocks before it when `fillsGap` is on.
    func logNow(_ categoryID: String) {
        now = Date()
        loadDayIfNeeded()
        let snapshot = snapshot
        guard let current = snapshot.status.currentIndex else { return }
        let start = fillsGap ? snapshot.unloggedRun(before: current).lowerBound : current
        set(start..<(current + 1), to: categoryID)
    }

    /// Stars a category, adding it to the palette, or unstars it.
    func toggleFavorite(_ id: String) {
        if let index = settings.favorites.firstIndex(of: id) {
            settings.favorites.remove(at: index)
        } else {
            settings.favorites.append(id)
        }
    }

    /// Adds an activity of your own to `track` (in `group`, for Activity) and returns its id. It isn't starred:
    /// it's a search away until you star it.
    func addActivity(in track: Track, group: CategoryGroup = .life) -> String {
        let category = BlockCategory.new(in: track, group: group)
        settings.customCategories.append(category)
        return category.id
    }

    /// Adds a group of your own, in the next of its colors, and returns its id.
    func addGroup() -> String {
        let colors = CategoryGroup.ownColors
        let group = CategoryGroup.new(color: colors[settings.customGroups.count % colors.count])
        settings.customGroups.append(group)
        return group.id
    }

    /// Removes an activity (or posture) from the palette, search and Settings' library; blocks logged with it keep
    /// it. Stops painting with it.
    func removeActivity(_ id: String) {
        settings.remove(id)
        for (track, brush) in brushes where brush.categoryID == id {
            brushes[track] = nil
        }
    }

    /// Removes a group of your own, once nothing is in it (but activities you removed, which fall back to Life).
    func removeGroup(_ id: String) {
        guard !settings.categories.contains(where: { $0.group?.id == id && !$0.isRetired }) else { return }
        settings.customGroups.removeAll { $0.id == id }
    }

    /// Adds a template, Lunch at 12:00 for 30 minutes every day to start with, and returns its id.
    func addTemplate() -> String {
        let activities = settings.categories.filter { $0.track == .activity && !$0.isRetired }
        let category = activities.first { $0.id == "lunch" } ?? activities.first
        let template = Template(categoryID: category?.id ?? "lunch", startMinute: 12 * 60, length: 6)
        settings.templates.append(template)
        return template.id
    }

    /// Starts moving today's schedule to `target` a step at a time, or changes the shift under way.
    func startSleepShift(_ shift: SleepShift, to target: Schedule) {
        var settings = settings
        settings.schedule = target
        settings.sleepShift = shift
        self.settings = settings
    }

    /// Sets today's times. A sleep shift carries on from them toward its target, from tomorrow night, or ends if
    /// they're there already.
    func setSchedule(_ today: Schedule) {
        guard let shift = settings.sleepShift else {
            settings.schedule = today
            return
        }
        var settings = settings
        let rebased = shift.rebased(onto: today, on: dayLog.day, target: settings.schedule)
        if rebased.stepCount(to: settings.schedule) == 0 {
            settings.schedule = today
            settings.sleepShift = nil
        } else {
            settings.sleepShift = rebased
        }
        self.settings = settings
    }

    /// Where a sleep shift has got to by this morning, or your schedule without one: what a new or edited shift
    /// moves on from, tonight's bedtime first.
    var shiftPosition: Schedule {
        settings.sleepShift?.position(on: dayLog.day, target: settings.schedule) ?? settings.schedule
    }

    /// Carries a sleep shift on from this morning with its next step on the night of `day`: tonight takes it, or a
    /// later night holds the steps back.
    func resumeSleepShift(nextStepOn day: String) {
        guard let shift = settings.sleepShift else { return }
        settings.sleepShift = shift.resumed(today: dayLog.day, nextStepOn: day, target: settings.schedule)
    }

    /// Stops a sleep shift where it's got to: today's schedule becomes the one you keep.
    func stopSleepShift() {
        var settings = settings
        settings.schedule = schedule
        settings.sleepShift = nil
        self.settings = settings
    }

    /// Switches to the next day's logs once the day rolls over.
    private func loadDayIfNeeded() {
        let day = settings.dayID(for: now)
        guard day != dayLog.day else { return }
        dayLog = store.load(day: day, wakeMinute: settings.schedule(on: day).wakeMinute)
        selection = nil
        // Yesterday's edits can't be undone over today.
        undoManager?.removeAllActions(withTarget: self)
        planDayIfNeeded()
        settings.endSleepShiftIfDone(on: day)
    }

    /// Lays the day's templates out the first time it's seen, the whole day, so a lunch you didn't change
    /// counts as lunch even when the app opens after it.
    private func planDayIfNeeded() {
        guard !dayLog.isPlanned else { return }
        dayLog.plan(settings.templates, schedule: schedule, categories: settings.categories)
        save()
    }

    /// Lays changed templates out again over the blocks still to come; what's already happened stays. Edits from
    /// before can't be undone after it: putting their logs back would take the new plan away too.
    private func replan() {
        undoManager?.removeAllActions(withTarget: self)
        let schedule = schedule
        let status = DayStatus(schedule: schedule, nowMinute: schedule.timelineMinute(for: now))
        dayLog.plan(
            settings.templates, from: status.currentIndex.map { $0 + 1 } ?? 0, schedule: schedule,
            categories: settings.categories)
        save()
    }
}
