import ImageIO
import SwiftUI
import TimeBlockKit
import UniformTypeIdentifiers

/// Writes a still PNG of every scenario, for reviewing the look without running the app.
@MainActor
enum Renderer {
    static func renderAll(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let standard = Schedule.standard
        var jobs = Scenario.all.map {
            (name: $0.id, scenario: $0, scheme: ColorScheme.dark, schedule: standard, track: Track.activity)
        }
        jobs += Scenario.all.prefix(3).map {
            (name: "\($0.id)-light", scenario: $0, scheme: ColorScheme.light, schedule: standard, track: Track.activity)
        }
        // Off-the-hour wake and bedtime: rows should still be clock hours.
        let halfPast = Schedule(wakeMinute: 8 * 60 + 30, bedMinute: 23 * 60 + 30)
        jobs.append((name: "wake-0830", scenario: Scenario.all[1], scheme: .dark, schedule: halfPast, track: .activity))
        jobs.append((
            name: "wake-0830-past-bed",
            scenario: Scenario(id: "late", title: "Bed at 23:30", clockMinute: 23 * 60 + 55),
            scheme: .dark, schedule: halfPast, track: .activity))
        // The Body view of the same day.
        for scenario in [Scenario.all[1], Scenario.all[2], Scenario.all[4]] {
            jobs.append((name: "\(scenario.id)-body", scenario: scenario, scheme: .dark, schedule: standard, track: .body))
        }

        for (number, job) in jobs.enumerated() {
            let schedule = job.schedule
            let snapshot = SampleDay.snapshot(
                schedule: schedule, nowMinute: schedule.timelineMinute(clockMinute: job.scenario.clockMinute),
                track: job.track)
            let window = "wake \(PrototypeView.clock(schedule.wakeMinute)), bed \(PrototypeView.clock(schedule.bedMinute))"
            let view = VStack(alignment: .leading, spacing: 18) {
                Text("\(PrototypeView.clock(job.scenario.clockMinute))  \(job.scenario.title)  ·  \(job.track.name)  ·  \(snapshot.status.blocksLeft) blocks  ·  \(window)")
                    .font(.system(size: 20, weight: .semibold))
                ScenarioBoard(snapshot: snapshot)
            }
            .padding(32)
            .background(job.scheme == .dark ? Color(white: 0.07) : Color(white: 0.94))
            .environment(\.colorScheme, job.scheme)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let url = directory.appendingPathComponent(String(format: "%02d-%@.png", number + 1, job.name))
            guard let image = renderer.cgImage,
                  let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
            else {
                print("Could not render \(job.name)")
                continue
            }
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
            print(url.path)
        }
    }
}
