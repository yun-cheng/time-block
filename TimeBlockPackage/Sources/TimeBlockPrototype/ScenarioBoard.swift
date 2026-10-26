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
    var animates = false

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 24) {
                labeled("Small widget") { WidgetMock(.small, snapshot: snapshot) }
                labeled("Medium widget") { WidgetMock(.medium, snapshot: snapshot) }
            }
            labeled("Large widget") { WidgetMock(.large, snapshot: snapshot) }
            labeled(animates ? "App (animated)" : "App") {
                // Blocks keep their size, so a long night makes the app taller rather than smaller.
                DayView(snapshot: snapshot, animates: animates)
                    .frame(width: 440)
                    .frame(minHeight: 660)
                    .fixedSize(horizontal: false, vertical: true)
                    // Set off from the board like the window.
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
