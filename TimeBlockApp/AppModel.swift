import Foundation
import Observation
import TimeBlockKit
import WidgetKit

@MainActor
@Observable
final class AppModel {
    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            SettingsStore.save(settings)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Ticks often enough for the menu bar count to flip on time at each 5-minute boundary.
    private(set) var now = Date()
    @ObservationIgnored private var timer: Timer?

    init() {
        settings = SettingsStore.load()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date() }
        }
    }

    var snapshot: DaySnapshot { settings.snapshot(at: now) }
}
