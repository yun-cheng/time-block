import SwiftUI
import TimeBlockKit
import TimeBlockUI

@main
struct TimeBlockApp: App {
    @State private var model = AppModel()

    #if os(macOS)
    init() {
        ClickAway.install()
    }
    #endif

    var body: some Scene {
        #if os(macOS)
        Window("Time Block", id: "main") {
            MainWindow(model: model)
        }
        .defaultSize(width: 480, height: 720)
        // The window follows the day: as wide as it, and shrunk to the compact day when it's kept on top.
        .windowResizability(.contentSize)
        // A slim toolbar with just the pin, the other buttons being in the day; the window keeps its name for the Window
        // menu and Mission Control.
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            TrackCommands(model: model)
            DayCommands(model: model)
            SettingsCommands(model: model)
            PinCommands(model: model)
        }

        MenuBarExtra {
            MenuBarPanel(model: model)
        } label: {
            MenuBarLabel(snapshot: model.snapshot)
        }
        .menuBarExtraStyle(.window)
        #else
        WindowGroup {
            MainWindow(model: model)
        }
        // A keyboard's shortcuts, in the iPad's menu.
        .commands {
            TrackCommands(model: model)
            DayCommands(model: model)
        }
        #endif
    }
}
