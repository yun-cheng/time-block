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
        // The toolbar is busy with the day's buttons; the window keeps its name for the Window menu and Mission Control.
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            TrackCommands(model: model)
            DayCommands(model: model)
            SettingsCommands(model: model)
        }

        MenuBarExtra {
            MenuBarPanel(model: model)
        } label: {
            MenuBarLabel(snapshot: model.snapshot)
        }
        .menuBarExtraStyle(.window)
    }
}
