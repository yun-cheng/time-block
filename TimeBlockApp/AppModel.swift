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

    /// Logs `range` in the current view as a category, or clears it with nil.
    func set(_ range: Range<Int>, to categoryID: String?) {
        loadDayIfNeeded()
        dayLog.set(range, to: categoryID, in: settings.track, schedule: schedule, categories: settings.categories)
        save()
    }

    /// Writes a note on the logged blocks of `range` in the current view, or takes it off with nil.
    func setNote(_ note: String?, for range: Range<Int>) {
        loadDayIfNeeded()
        dayLog.setNote(note, for: range, in: settings.track, schedule: schedule, categories: settings.categories)
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

    /// Starts moving today's schedule to `target` a step at a time.
    func startSleepShift(_ shift: SleepShift, to target: Schedule) {
        var settings = settings
        settings.schedule = target
        settings.sleepShift = shift
        self.settings = settings
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

    /// Lays changed templates out again over the blocks still to come; what's already happened stays.
    private func replan() {
        let schedule = schedule
        let status = DayStatus(schedule: schedule, nowMinute: schedule.timelineMinute(for: now))
        dayLog.plan(
            settings.templates, from: status.currentIndex.map { $0 + 1 } ?? 0, schedule: schedule,
            categories: settings.categories)
        save()
    }
}
