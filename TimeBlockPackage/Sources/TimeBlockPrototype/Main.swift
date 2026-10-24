import AppKit
import SwiftUI

/// `swift run TimeBlockPrototype` opens the playground window;
/// `swift run TimeBlockPrototype --render <dir>` writes a PNG per scenario instead.
@main
enum PrototypeMain {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if let flag = args.firstIndex(of: "--render") {
            let path = args.indices.contains(flag + 1) ? args[flag + 1] : "renders"
            Renderer.renderAll(to: URL(fileURLWithPath: path))
        } else {
            PrototypeApp.main()
        }
    }
}

struct PrototypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Time Block — M0 Prototype") {
            PrototypeView()
        }
        .defaultSize(width: 1440, height: 920)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `swift run` launches a bare executable; make it a regular foreground app with a Dock icon.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
}
