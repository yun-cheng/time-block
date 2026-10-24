import AppKit
import SwiftUI
import TimeBlockKit
import TimeBlockUI

/// "▦ 92/192" in the menu bar. Menu bar items are monochrome, so the symbol carries the mood.
struct MenuBarLabel: View {
    let snapshot: DaySnapshot

    var body: some View {
        let status = snapshot.status
        let count = status.blocksLeft < 0 ? "\u{2212}\(-status.blocksLeft)" : "\(status.blocksLeft)"
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text("\(count)/\(status.schedule.awakeBlocks)").monospacedDigit()
        }
    }

    private var symbol: String {
        switch snapshot.mood {
        case .calm: "square.grid.3x3.fill"
        case .windDown: "moon.fill"
        case .uneasy: "moon.zzz.fill"
        case .dread, .nightmare: "exclamationmark.triangle.fill"
        }
    }
}

struct MenuBarPanel: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let snapshot = model.snapshot
        let theme = MoodTheme(mood: snapshot.mood, colorScheme: colorScheme)
        VStack(spacing: 0) {
            WidgetContent(family: .medium, snapshot: snapshot, theme: theme)
                .frame(height: 170)
                .background(MoodBackground(theme: theme))
            Divider()
            HStack {
                TrackPicker(track: $model.settings.track)
                    .fixedSize()
                Spacer()
                Button {
                    openWindow(id: "main")
                    NSApp.activate()
                } label: {
                    Image(systemName: "macwindow")
                }
                .help("Open Time Block")
                Button {
                    showSettings(model, openWindow: openWindow)
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit Time Block")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 364)
    }
}
