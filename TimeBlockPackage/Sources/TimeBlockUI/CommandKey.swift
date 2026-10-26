#if canImport(AppKit)
import AppKit
#endif
import SwiftUI

#if canImport(AppKit)
/// Keeps `isDown` up to date with whether ⌘ is held, so a pointer can change the moment it's pressed.
struct CommandKeyTracker: ViewModifier {
    @Binding var isDown: Bool
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                isDown = NSEvent.modifierFlags.contains(.command)
                let isDown = $isDown
                monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                    let held = event.modifierFlags.contains(.command)
                    MainActor.assumeIsolated { isDown.wrappedValue = held }
                    return event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

/// Shows `cursor` while the pointer is over the view, or the usual one with nil.
struct HoverCursor: ViewModifier {
    let cursor: NSCursor?
    @State private var isInside = false

    func body(content: Content) -> some View {
        content
            .onHover { isInside = $0 }
            .onChange(of: isInside ? cursor : nil) { old, new in
                if old != nil { NSCursor.pop() }
                new?.push()
            }
    }
}
#endif

extension View {
    /// Tracks whether ⌘ is held (always false where there's no keyboard to ask).
    func tracksCommandKey(_ isDown: Binding<Bool>) -> some View {
        #if canImport(AppKit)
        modifier(CommandKeyTracker(isDown: isDown))
        #else
        self
        #endif
    }
}
