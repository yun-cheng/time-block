import SwiftUI
import TimeBlockKit
import TimeBlockUI

struct PrototypeView: View {
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: Self { self }
        var scheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    /// Minute on the day's timeline, so it can run past midnight.
    @State private var nowMinute = 15 * 60 + 20
    @State private var wakeMinute = 7 * 60
    /// May exceed 24:00 for a bedtime after midnight.
    @State private var bedMinute = 23 * 60
    @State private var track = Track.activity
    @State private var appearance = Appearance.system
    @State private var animate = true

    private var schedule: Schedule {
        Schedule(wakeMinute: wakeMinute, bedMinute: bedMinute % (24 * 60))
    }

    var body: some View {
        let snapshot = SampleDay.snapshot(schedule: schedule, nowMinute: nowMinute, track: track)
        HStack(spacing: 0) {
            controls(snapshot)
                .frame(width: 250)
                .frame(maxHeight: .infinity, alignment: .top)
            Divider()
            ScrollView([.horizontal, .vertical]) {
                TimelineView(.animation(paused: !animate)) { context in
                    let time = animate ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000) : 0
                    ScenarioBoard(snapshot: snapshot, time: time)
                }
                .padding(28)
            }
        }
        .preferredColorScheme(appearance.scheme)
    }

    private func controls(_ snapshot: DaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Time Block").font(.title2.bold())
                Text("M0 visual prototype").foregroundStyle(.secondary)
            }

            GroupBox("Time") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Self.clock(nowMinute))
                        .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    Slider(
                        value: Binding(get: { Double(nowMinute) }, set: { nowMinute = Int($0) / 5 * 5 }),
                        in: Double(wakeMinute - 60)...Double(schedule.bedTimelineMinute + 240))
                    Text("\(snapshot.status.blocksLeft) blocks · \(String(describing: snapshot.mood))")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Jump to") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Scenario.all) { scenario in
                        Button("\(Self.clock(scenario.clockMinute))  \(scenario.title)") {
                            nowMinute = schedule.timelineMinute(clockMinute: scenario.clockMinute)
                        }
                        .buttonStyle(.link)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Schedule") {
                VStack(alignment: .leading) {
                    Stepper("Wake  \(Self.clock(wakeMinute))", value: $wakeMinute, in: (4 * 60)...(11 * 60), step: 30)
                    Stepper("Bed   \(Self.clock(bedMinute))", value: $bedMinute, in: (20 * 60)...(26 * 60), step: 30)
                }
                .font(.body.monospacedDigit())
            }

            Picker("View", selection: $track) {
                ForEach(Track.allCases, id: \.self) { Label($0.name, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.rawValue.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Animate app view", isOn: $animate)

            Spacer()
            Text("Widgets are drawn as still frames because WidgetKit can't animate. Only the app view moves.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
    }

    static func clock(_ minute: Int) -> String {
        let m = ((minute % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}
