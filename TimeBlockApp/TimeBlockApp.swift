import SwiftUI
import TimeBlockKit
import TimeBlockUI

@main
struct TimeBlockApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Time Block", id: "main") {
            MainWindow(model: model)
        }
        .defaultSize(width: 480, height: 720)
        .commands { TrackCommands(model: model) }

        MenuBarExtra {
            MenuBarPanel(model: model)
        } label: {
            MenuBarLabel(snapshot: model.snapshot)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
