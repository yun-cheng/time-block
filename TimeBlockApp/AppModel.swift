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
            // Block indexes count from wake time, so a selection would point at other times.
            if settings.schedule != oldValue.schedule { selection = nil }
            SettingsStore.save(settings)
            loadDayIfNeeded()
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
        let settings = SettingsStore.load()
        self.settings = settings
        dayLog = store.load(day: settings.schedule.dayID(for: .now), wakeMinute: settings.schedule.wakeMinute)
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.now = Date()
                self?.loadDayIfNeeded()
            }
        }
    }

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
        dayLog.set(range, to: categoryID, in: settings.track, schedule: settings.schedule, categories: settings.categories)
        save()
    }

    /// Writes a note on the logged blocks of `range` in the current view, or takes it off with nil.
    func setNote(_ note: String?, for range: Range<Int>) {
        loadDayIfNeeded()
        dayLog.setNote(note, for: range, in: settings.track, schedule: settings.schedule, categories: settings.categories)
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

    /// Removes a group of your own, once nothing is in it.
    func removeGroup(_ id: String) {
        guard !settings.categories.contains(where: { $0.group?.id == id }) else { return }
        settings.customGroups.removeAll { $0.id == id }
    }

    /// Switches to the next day's logs once the day rolls over.
    private func loadDayIfNeeded() {
        let day = settings.schedule.dayID(for: now)
        guard day != dayLog.day else { return }
        dayLog = store.load(day: day, wakeMinute: settings.schedule.wakeMinute)
        selection = nil
    }
}
