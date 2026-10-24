import SwiftUI
import TimeBlockKit
import TimeBlockUI

struct Scenario: Identifiable, Sendable {
    let id: String
    let title: String
    let clockMinute: Int

    static let all: [Scenario] = [
        Scenario(id: "morning", title: "Morning", clockMinute: 9 * 60 + 40),
        Scenario(id: "afternoon", title: "Afternoon", clockMinute: 15 * 60 + 20),
        Scenario(id: "winddown", title: "Wind-down", clockMinute: 22 * 60 + 40),
        Scenario(id: "uneasy", title: "Just past bedtime", clockMinute: 23 * 60 + 20),
        Scenario(id: "dread", title: "Way past bedtime", clockMinute: 40),
        Scenario(id: "nightmare", title: "Nightmare", clockMinute: 2 * 60 + 30),
    ]
}

/// Every surface side by side for one moment of the day.
struct ScenarioBoard: View {
    let snapshot: DaySnapshot
    var time: Double = 0

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 24) {
                labeled("Small widget") { WidgetMock(.small, snapshot: snapshot) }
                labeled("Medium widget") { WidgetMock(.medium, snapshot: snapshot) }
            }
            labeled("Large widget") { WidgetMock(.large, snapshot: snapshot) }
            labeled(time > 0 ? "App (animated)" : "App") {
                DayView(snapshot: snapshot, time: time).frame(width: 440, height: 660)
            }
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
