import AppKit

/// Ends typing when you click outside what's being typed in, as on the web: on its own, a Mac window keeps a field
/// focused through clicks on the space around it. The click goes on to do whatever it does, and one on another field
/// moves the typing there as usual.
@MainActor
enum ClickAway {
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            endTyping(for: event)
            return event
        }
    }

    private static func endTyping(for event: NSEvent) {
        guard let window = event.window, window.firstResponder is NSText,
              let root = window.contentView?.superview
        else { return }
        var view = root.hitTest(event.locationInWindow)
        while let current = view {
            // Text you can type in, or a time field: the click is for it.
            if current is NSText || current is NSTextField || current is NSDatePicker { return }
            view = current.superview
        }
        window.makeFirstResponder(nil)
    }
}
