import AppKit
import SwiftUI

extension View {
    /// Gives the scroll view this sits in (the rows of a `Form`) the app's scroll bar: always shown while there's
    /// more to scroll, as a thin knob with no track behind it, in a narrow lane on the right. The Mac's own
    /// always-on scroll bar sits in a wide dark track that throws margins off. For a `ScrollView`, use
    /// `AppScrollView`, which draws the same scroll bar where it shows.
    func appScrollBar() -> some View {
        background(ScrollBarProbe())
    }
}

/// The width of the lane the app's scroll bar keeps on the right of a scroll view.
private let scrollBarLane: CGFloat = 12

/// Finds the scroll view around it once it's in a window, and fits it with a `ClearScroller`.
private struct ScrollBarProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard window != nil else { return }
            apply()
            // The scroll view goes back to the system's style when that setting changes; fit it again then.
            NotificationCenter.default.addObserver(
                self, selector: #selector(apply), name: NSScroller.preferredScrollerStyleDidChangeNotification,
                object: nil)
        }

        @objc private func apply() {
            // The scroll view is set up once the hosting view has laid out.
            DispatchQueue.main.async { [weak self] in
                guard let scrollView = self?.enclosingScrollView else { return }
                // The always-on kind, drawn by the scroller itself; the floating kind fades out on its own.
                scrollView.scrollerStyle = .legacy
                if !(scrollView.verticalScroller is ClearScroller) {
                    scrollView.verticalScroller = ClearScroller()
                }
                scrollView.verticalScroller?.scrollerStyle = .legacy
                // Keep the lane even with nothing to scroll, so margins don't shift as content grows.
                scrollView.hasVerticalScroller = true
                scrollView.autohidesScrollers = false
                self?.fitScroller(to: scrollView)
                if let self, self.observed !== scrollView {
                    self.observed = scrollView
                    scrollView.postsFrameChangedNotifications = true
                    NotificationCenter.default.addObserver(
                        self, selector: #selector(self.frameChanged), name: NSView.frameDidChangeNotification,
                        object: scrollView)
                }
            }
        }

        private weak var observed: NSScrollView?

        @objc private func frameChanged() {
            if let observed { fitScroller(to: observed) }
        }

        /// Keeps the scroll bar inside the part of the scroll view that shows, out from under the toolbar.
        private func fitScroller(to scrollView: NSScrollView) {
            let bounds = scrollView.bounds
            var visible = scrollView.visibleRect
            if let content = scrollView.window?.contentView {
                visible = visible.intersection(scrollView.convert(content.safeAreaRect, from: content))
            }
            guard !visible.isEmpty else { return }
            let hiddenTop = scrollView.isFlipped ? visible.minY - bounds.minY : bounds.maxY - visible.maxY
            let hiddenBottom = scrollView.isFlipped ? bounds.maxY - visible.maxY : visible.minY - bounds.minY
            let insets = NSEdgeInsets(
                top: hiddenTop, left: 0, bottom: hiddenBottom, right: bounds.maxX - visible.maxX)
            let current = scrollView.scrollerInsets
            guard current.top != insets.top || current.bottom != insets.bottom || current.right != insets.right
            else { return }
            scrollView.scrollerInsets = insets
            scrollView.tile()
        }
    }
}

/// A vertical scroll bar in a narrow lane that draws only its knob, thin and rounded: no track, no border.
private final class ClearScroller: NSScroller {
    private var isHovered = false
    private var tracking: NSTrackingArea?

    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        scrollBarLane
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // In a layer of its own: drawn straight into the scroll view's, it left its picture behind when it moved
        // (as when Settings opens and the main view's scroll bar steps out from under it).
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    // AppKit only redraws where the knob is now; redraw the whole lane so the old knob doesn't linger.
    override var knobProportion: CGFloat {
        didSet { needsDisplay = true }
    }

    override var doubleValue: Double {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        // Nothing to scroll, nothing to show.
        guard knobProportion < 1, usableParts == .allScrollerParts else { return }
        let slot = rect(for: .knob)
        let width = KnobLook.width(hovered: isHovered)
        let knob = NSRect(x: bounds.midX - width / 2, y: slot.minY + 2, width: width, height: slot.height - 4)
        NSColor.labelColor.withAlphaComponent(KnobLook.opacity(hovered: isHovered)).setFill()
        NSBezierPath(roundedRect: knob, xRadius: width / 2, yRadius: width / 2).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }
}

/// How the app's scroll bar knob looks, wherever it's drawn.
private enum KnobLook {
    static func width(hovered: Bool) -> CGFloat { hovered ? 9 : 7 }
    static func opacity(hovered: Bool) -> CGFloat { hovered ? 0.45 : 0.3 }
}

/// A vertical scroll view with the app's scroll bar drawn by SwiftUI in a `lane` along its right edge, inside the
/// content's margin. For scroll views AppKit's scroll bar can't be fitted to: on the Mac, SwiftUI runs a scroll
/// view's AppKit frame past what shows (out past a popover's bubble, under the inspector), taking an AppKit scroll
/// bar with it.
struct AppScrollView<Content: View>: View {
    let lane: CGFloat
    @ViewBuilder let content: Content

    @State private var scrolled: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    private static var space: String { "AppScrollView" }
    private static var contentID: String { "AppScrollView.content" }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                    .id(Self.contentID)
                    .background {
                        // Followed from inside: a preference from inside a scroll view doesn't make it out on the Mac.
                        GeometryReader { geometry in
                            let frame = geometry.frame(in: .named(Self.space))
                            Color.clear
                                .onAppear { follow(frame) }
                                .onChange(of: frame) { _, frame in follow(frame) }
                        }
                    }
            }
            .coordinateSpace(name: Self.space)
            .scrollIndicators(.never)
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { viewportHeight = geometry.size.height }
                        .onChange(of: geometry.size.height) { _, height in viewportHeight = height }
                }
            }
            .overlay(alignment: .trailing) {
                if contentHeight > viewportHeight + 1 {
                    ScrollKnob(
                        progress: scrolled / (contentHeight - viewportHeight),
                        proportion: viewportHeight / contentHeight
                    ) { fraction in
                        // Lines the content's point at `fraction` of its height up with the same point of the view.
                        proxy.scrollTo(Self.contentID, anchor: UnitPoint(x: 0.5, y: fraction))
                    }
                    .frame(width: lane)
                }
            }
        }
    }

    private func follow(_ frame: CGRect) {
        scrolled = -frame.minY
        contentHeight = frame.height
    }
}

/// The app's scroll bar knob drawn in SwiftUI, filling the height it's given; dragging the knob or clicking along
/// it asks to `seek` to that point, from 0 (top) to 1 (bottom).
private struct ScrollKnob: View {
    /// How far down the content is scrolled, from 0 to 1.
    let progress: CGFloat
    /// How much of the content is in view, from 0 to 1.
    let proportion: CGFloat
    let seek: (CGFloat) -> Void
    @State private var isHovered = false

    var body: some View {
        GeometryReader { track in
            let inset: CGFloat = 2
            let travel = track.size.height - 2 * inset
            let length = max(24, travel * min(1, proportion))
            let offset = inset + (travel - length) * min(1, max(0, progress))
            let width = KnobLook.width(hovered: isHovered)
            Capsule()
                .fill(Color.primary.opacity(KnobLook.opacity(hovered: isHovered)))
                .frame(width: width, height: length)
                .position(x: track.size.width / 2, y: offset + length / 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { drag in
                        let fraction = (drag.location.y - inset - length / 2) / max(1, travel - length)
                        seek(min(1, max(0, fraction)))
                    })
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: 0.1), value: isHovered)
        }
    }
}
