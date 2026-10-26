import Foundation
import Observation
import os
import TimeBlockKit
import TimeBlockUI
import UserNotifications
import WidgetKit

@MainActor
@Observable
final class AppModel {
    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            let scheduleChanged = settings.schedule(on: dayLog.day) != oldValue.schedule(on: dayLog.day)
            // Block indexes count from wake time, so a selection would point at other times.
            if scheduleChanged && shownDay >= dayLog.day { selection = nil }
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

    /// The day the window shows when it isn't today: a past day, or one still to come.
    private(set) var otherLog: DayLog?

    /// Whether the main window shows the settings inspector.
    var showsSettings = false

    /// Whether activities replace what blocks hold or are added to it.
    var tool: Tool = .normal

    /// Blocks selected in the window, waiting for a category.
    var selection: Range<Int>? {
        didSet { if selection == nil { selectedLayer = nil } }
    }

    /// The one activity of the selected blocks picked out, by clicking its card of a stack; nil for all they hold.
    var selectedLayer: String?

    /// The timers going, which log their activities live. They're saved, so they carry on when the app quits, and
    /// the widget shows what they log.
    private(set) var timers: [LiveTimer] {
        didSet {
            guard timers != oldValue else { return }
            TimerStore.save(timers)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// What new timers count down from, in minutes, or nil to count up.
    var countdownMinutes: Int? {
        didSet { UserDefaults.standard.set(countdownMinutes ?? 0, forKey: "countdownMinutes") }
    }

    /// Ticks often enough for the menu bar count to flip on time at each 5-minute boundary.
    private(set) var now = Date()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let store = LogStore.shared
    @ObservationIgnored private let logger = Logger(subsystem: "dev.timeblock.TimeBlock", category: "logs")
    @ObservationIgnored private let alarms = Alarms()

    init() {
        var settings = SettingsStore.load()
        let day = settings.dayID(for: .now)
        if settings.endSleepShiftIfDone(on: day) { SettingsStore.save(settings) }
        self.settings = settings
        dayLog = store.load(day: day, wakeMinute: settings.schedule(on: day).wakeMinute)
        timers = TimerStore.load()
        let minutes = UserDefaults.standard.integer(forKey: "countdownMinutes")
        countdownMinutes = minutes > 0 ? minutes : nil
        planDayIfNeeded()
        keepTodaysSchedule()
        // The widget may have drawn the day before it could see what's saved, as on the first signed launch.
        WidgetCenter.shared.reloadAllTimelines()
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
        settings.snapshot(at: date, log: dayLog, timers: timers)
    }

    // MARK: Other days

    /// The day the window shows.
    var shownDay: String { otherLog?.day ?? dayLog.day }

    var isShowingToday: Bool { otherLog == nil }

    /// What the window shows at `date`: today then, or the other day you went to.
    func shownSnapshot(at date: Date) -> DaySnapshot {
        otherLog.map { settings.snapshot(of: $0, today: dayLog.day) } ?? snapshot(at: date)
    }

    /// Shows `day` in the window, any day at all.
    func show(_ day: String) {
        loadDayIfNeeded()
        guard day != shownDay else { return }
        otherLog = day == dayLog.day ? nil : load(day)
        selection = nil
    }

    /// The saved logs of a day other than today. A day still to come has its templates laid out, the way it will
    /// when it comes, but that's only saved once it's changed.
    private func load(_ day: String) -> DayLog {
        var log = store.load(day: day, wakeMinute: settings.schedule(on: day).wakeMinute)
        if day > dayLog.day, !log.isPlanned {
            log.plan(settings.templates, schedule: schedule(of: log), categories: settings.categories)
        }
        return log
    }

    /// The schedule of a day: today's and those to come follow the settings, and past days keep their own.
    private func schedule(of log: DayLog) -> Schedule {
        settings.schedule(of: log, today: dayLog.day)
    }

    /// Shows the day `offset` days from the one shown.
    func showDay(_ offset: Int) {
        if let day = DayID.adding(offset, to: shownDay) { show(day) }
    }

    func showToday() { show(dayLog.day) }

    /// The main window's undo manager. Block edits are registered with it, so Edit ▸ Undo takes them back.
    @ObservationIgnored weak var undoManager: UndoManager?

    /// Logs `range` in the current view of the day shown as a category, or clears it with nil. With `layer`, only that
    /// activity is replaced or cleared.
    func set(_ range: Range<Int>, to categoryID: String?, layer: String? = nil) {
        set(range, to: categoryID, layer: layer, on: shownDay)
    }

    private func set(_ range: Range<Int>, to categoryID: String?, layer: String? = nil, on day: String) {
        let name = layer == nil
            ? categoryID == nil ? "Clear Blocks" : "Log Blocks"
            : categoryID == nil ? "Remove Activity" : "Replace Activity"
        edit(name, on: day) {
            $0.set(range, to: categoryID, in: settings.track, schedule: $1, categories: settings.categories, layer: layer)
        }
    }

    /// Adds an activity to what `range` holds in the day shown, or takes it off when every block holds it.
    func toggle(_ range: Range<Int>, _ categoryID: String) {
        toggle(range, categoryID, on: shownDay)
    }

    private func toggle(_ range: Range<Int>, _ categoryID: String, on day: String) {
        guard let log = log(of: day) else { return }
        let isHeld = log.holds(categoryID, throughout: range, schedule: schedule(of: log))
        edit(isHeld ? "Remove Activity" : "Add Activity", on: day) {
            $0.toggle(categoryID, in: range, schedule: $1, categories: settings.categories)
        }
    }

    /// Moves the ends of the run of one activity at `range` in the current view to `newRange`; with `layer`, of that
    /// activity among others.
    func resize(_ range: Range<Int>, to newRange: Range<Int>, layer: String? = nil) {
        edit("Resize Blocks", on: shownDay) {
            $0.resize(range, to: newRange, in: settings.track, schedule: $1, categories: settings.categories, layer: layer)
        }
    }

    /// Moves what `range` holds in the current view `offset` blocks along, or just `layer` of it.
    func move(_ range: Range<Int>, by offset: Int, layer: String? = nil) {
        edit("Move Blocks", on: shownDay) {
            $0.move(range, by: offset, in: settings.track, schedule: $1, categories: settings.categories, layer: layer)
        }
    }

    /// Writes a note on the logged blocks of `range` in the current view, or on `layer` of them, or takes it off with
    /// nil.
    func setNote(_ note: String?, for range: Range<Int>, layer: String? = nil) {
        edit(note == nil ? "Remove Note" : "Edit Note", on: shownDay) {
            $0.setNote(note, for: range, in: settings.track, schedule: $1, categories: settings.categories, layer: layer)
        }
    }

    /// What an undo puts back: a day's logs, and the view and selection they were edited in.
    private struct UndoPoint: Sendable {
        let log: DayLog
        let track: Track
        let selection: Range<Int>?
        var layer: String?
    }

    /// Makes a change to the logs of `day`, today or the past day shown, which can be undone as `name`. The change
    /// is given the day's schedule.
    private func edit(_ name: String, on day: String, _ change: (inout DayLog, Schedule) -> Void) {
        loadDayIfNeeded()
        guard let before = log(of: day) else { return }
        var log = before
        change(&log, schedule(of: log))
        guard log != before else { return }
        put(log)
        registerUndo(name, restoring: UndoPoint(log: before, track: settings.track, selection: selection, layer: selectedLayer))
        save(log)
    }

    /// The logs of `day`, when it's today or the other day shown.
    private func log(of day: String) -> DayLog? {
        day == dayLog.day ? dayLog : otherLog?.day == day ? otherLog : nil
    }

    /// Takes `log` as its day's logs: today's, or the other day's shown.
    private func put(_ log: DayLog) {
        if log.day == dayLog.day { dayLog = log } else { otherLog = log }
    }

    private func registerUndo(_ name: String, restoring point: UndoPoint) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { $0.restore(point, name: name) }
        undoManager.setActionName(name)
    }

    /// Puts a day's logs back as they were, showing the day and view they changed in, and registers the way back (a
    /// redo, after an undo).
    private func restore(_ point: UndoPoint, name: String) {
        loadDayIfNeeded()
        show(point.log.day)
        guard let log = log(of: point.log.day) else { return }
        let isSameTrack = settings.track == point.track
        let current = UndoPoint(
            log: log, track: point.track, selection: isSameTrack ? selection : nil, layer: isSameTrack ? selectedLayer : nil)
        put(point.log)
        settings.track = point.track
        selection = point.selection
        selectedLayer = point.layer
        registerUndo(name, restoring: current)
        save(point.log)
    }

    private func save(_ log: DayLog? = nil) {
        let log = log ?? dayLog
        do {
            try store.save(log)
        } catch {
            logger.error("Couldn't save \(log.day): \(error)")
        }
        if log.day == dayLog.day { WidgetCenter.shared.reloadAllTimelines() }
    }

    // MARK: Timers

    /// Starts a timer of an activity, counting as `countdownMinutes` says, unless the activity has one going already.
    func startTimer(_ categoryID: String) {
        now = Date()
        guard !timers.contains(where: { $0.categoryID == categoryID }) else { return }
        let timer = LiveTimer(
            categoryID: categoryID, countdown: countdownMinutes.map { TimeInterval($0 * 60) }, startedAt: now)
        timers.append(timer)
        alarms.set(for: timer, name: name(of: categoryID), at: now)
    }

    /// Stops a timer, logging what it ran.
    func stopTimer(_ id: UUID) {
        now = Date()
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        let timer = timers.remove(at: index)
        alarms.cancel(id)
        record(timer.session(at: now), as: "Stop Timer")
    }

    /// Drops a timer without logging what it ran.
    func deleteTimer(_ id: UUID) {
        timers.removeAll { $0.id == id }
        alarms.cancel(id)
    }

    /// Logs a stretch a timer ran on each day it ran on, unless it was too short to mean it.
    private func record(_ session: TimerSession, as name: String) {
        guard session.duration >= TimerSession.shortest else { return }
        loadDayIfNeeded()
        for day in Set([settings.dayID(for: session.start), settings.dayID(for: session.end)]).sorted() {
            if log(of: day) != nil {
                edit(name, on: day) { $0.record(session, schedule: $1) }
            } else {
                var log = store.load(day: day, wakeMinute: settings.schedule(on: day).wakeMinute)
                log.record(session, schedule: schedule(of: log))
                save(log)
            }
        }
    }

    private func name(of categoryID: String) -> String {
        settings.categories.first { $0.id == categoryID }?.name ?? categoryID
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
    /// it.
    func removeActivity(_ id: String) {
        settings.remove(id)
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

    /// Switches to the next day's logs once the day rolls over. The window moves on with it when it shows today.
    private func loadDayIfNeeded() {
        let day = settings.dayID(for: now)
        guard day != dayLog.day else { return }
        dayLog = store.load(day: day, wakeMinute: settings.schedule(on: day).wakeMinute)
        if otherLog == nil { selection = nil }
        // The day you went ahead to has come.
        if otherLog?.day == day { otherLog = nil }
        planDayIfNeeded()
        keepTodaysSchedule()
        settings.endSleepShiftIfDone(on: day)
    }

    /// Keeps today's schedule with its logs, so the day keeps its length once it's over.
    private func keepTodaysSchedule() {
        guard dayLog.schedule != schedule else { return }
        dayLog.rebase(to: schedule)
        save()
    }

    /// Lays the day's templates out the first time it's seen, the whole day, so a lunch you didn't change
    /// counts as lunch even when the app opens after it.
    private func planDayIfNeeded() {
        guard !dayLog.isPlanned else { return }
        dayLog.plan(settings.templates, schedule: schedule, categories: settings.categories)
        save()
    }

    /// Lays changed templates out again over the blocks still to come, today's and those of the days ahead already
    /// planned; what's already happened stays. Edits from before can't be undone after it: putting their logs back
    /// would take the new plan away too.
    private func replan() {
        undoManager?.removeAllActions(withTarget: self)
        let schedule = schedule
        let status = DayStatus(schedule: schedule, nowMinute: schedule.timelineMinute(for: now))
        dayLog.plan(
            settings.templates, from: status.currentIndex.map { $0 + 1 } ?? 0, schedule: schedule,
            categories: settings.categories)
        save()
        for day in store.savedDays() where day > dayLog.day {
            var log = store.load(day: day, wakeMinute: settings.schedule(on: day).wakeMinute)
            guard log.isPlanned else { continue }
            log.plan(settings.templates, schedule: self.schedule(of: log), categories: settings.categories)
            save(log)
        }
        if let day = otherLog?.day, day > dayLog.day { otherLog = load(day) }
    }
}

/// Says when a countdown gets to zero, with a notification and a sound, even while the app is in front. The timer
/// keeps counting past it.
private final class Alarms: NSObject, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Sets the alarm for a countdown, asking leave to notify the first time.
    func set(for timer: LiveTimer, name: String, at date: Date) {
        guard let zero = timer.zeroDate, let countdown = timer.countdown, zero > date else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(name): time's up"
        content.body = "\(Int(countdown) / 60) min done. The timer keeps going until you stop it."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: timer.id.uuidString, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: zero.timeIntervalSince(date), repeats: false))
        let center = UNUserNotificationCenter.current()
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            try? await center.add(request)
        }
    }

    func cancel(_ id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
