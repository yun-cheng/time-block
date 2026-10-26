import SwiftUI
import TimeBlockUI

extension View {
    /// Holds the day's animations and timers still while its window can't be seen at all, or while `isPaused`.
    func pausesAnimationWhenHidden(or isPaused: Bool = false) -> some View {
        modifier(PausesWhenHidden(isPaused: isPaused))
    }
}

private struct PausesWhenHidden: ViewModifier {
    let isPaused: Bool
    @State private var isVisible = true

    func body(content: Content) -> some View {
        content
            .environment(\.pausesAnimation, isPaused || !isVisible)
            #if os(macOS)
            .background(WindowVisibility(isVisible: $isVisible))
            #endif
    }
}

#if os(macOS)
import AppKit

/// Whether the window it's in shows any of itself: not covered by other windows, minimized, on another Space, or
/// closed, like the menu bar's panel once it's gone.
private struct WindowVisibility: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> WatchingView { WatchingView() }

    func updateNSView(_ view: WatchingView, context: Context) {
        view.changed = { isVisible = $0 }
    }

    final class WatchingView: NSView {
        var changed: ((Bool) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let center = NotificationCenter.default
            center.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
            if let window {
                center.addObserver(
                    self, selector: #selector(occlusionChanged), name: NSWindow.didChangeOcclusionStateNotification,
                    object: window)
            }
            occlusionChanged()
        }

        @objc private func occlusionChanged() {
            let isVisible = window?.occlusionState.contains(.visible) ?? false
            // Not while SwiftUI is updating the view it's in.
            DispatchQueue.main.async { [weak self] in self?.changed?(isVisible) }
        }
    }
}
#endif
