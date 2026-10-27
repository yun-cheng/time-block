import QuartzCore
import SwiftUI

/// The current block's ring, brightening and dimming as long as it shows. Core Animation runs it, outside the app, so
/// it costs nothing between frames; a SwiftUI clock would lay out and render the whole window again for each one.
struct PulsingRing: View {
    let cornerRadius: CGFloat
    let lineWidth: CGFloat
    let color: Color
    @Environment(\.pausesAnimation) private var isPaused

    /// Dimmest to brightest, then back: the pulse a SwiftUI clock would draw, 0.55 + 0.45 · sin(4t).
    static let dimmest: Float = 0.1
    static let halfPeriod: CFTimeInterval = .pi / 4

    var body: some View {
        RingLayer(cornerRadius: cornerRadius, lineWidth: lineWidth, color: color, isPaused: isPaused)
            .allowsHitTesting(false)
    }
}

/// The layer itself, stroked along the middle of its bounds, which are as big as the ring and its line.
private struct RingLayer {
    let cornerRadius: CGFloat
    let lineWidth: CGFloat
    let color: Color
    let isPaused: Bool

    @MainActor static func update(_ layer: CAShapeLayer, with ring: RingLayer, in environment: EnvironmentValues) {
        let rect = layer.bounds.insetBy(dx: ring.lineWidth / 2, dy: ring.lineWidth / 2)
        layer.path = rect.width > 0 && rect.height > 0
            ? CGPath(roundedRect: rect, cornerWidth: ring.cornerRadius, cornerHeight: ring.cornerRadius, transform: nil)
            : nil
        layer.fillColor = nil
        layer.strokeColor = ring.color.resolve(in: environment).cgColor
        layer.lineWidth = ring.lineWidth
        if ring.isPaused {
            layer.removeAnimation(forKey: "pulse")
        } else if layer.animation(forKey: "pulse") == nil {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = PulsingRing.dimmest
            pulse.duration = PulsingRing.halfPeriod
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            // Kept while the app is in the background, which would otherwise drop it until the ring is next laid out.
            pulse.isRemovedOnCompletion = false
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            // As smooth as the rest of the day's animations, and no more.
            pulse.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 15, preferred: 15)
            layer.add(pulse, forKey: "pulse")
        }
    }
}

#if canImport(AppKit)
import AppKit

extension RingLayer: NSViewRepresentable {
    func makeNSView(context: Context) -> RingView { RingView() }

    func updateNSView(_ view: RingView, context: Context) {
        view.ring = self
        view.environment = context.environment
        view.needsLayout = true
    }

    final class RingView: NSView {
        var ring: RingLayer?
        var environment = EnvironmentValues()
        private let shape = CAShapeLayer()

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            layer?.addSublayer(shape)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            update()
        }

        // A layer's animations are dropped when it leaves a window.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            update()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func update() {
            guard let ring else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            shape.frame = bounds
            RingLayer.update(shape, with: ring, in: environment)
            CATransaction.commit()
        }
    }
}
#else
import UIKit

extension RingLayer: UIViewRepresentable {
    func makeUIView(context: Context) -> RingView { RingView() }

    func updateUIView(_ view: RingView, context: Context) {
        view.ring = self
        view.environment = context.environment
        view.setNeedsLayout()
    }

    final class RingView: UIView {
        var ring: RingLayer?
        var environment = EnvironmentValues()
        override class var layerClass: AnyClass { CAShapeLayer.self }

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            update()
        }

        // A layer's animations are dropped when it leaves a window.
        override func didMoveToWindow() {
            super.didMoveToWindow()
            update()
        }

        private func update() {
            guard let ring, let shape = layer as? CAShapeLayer else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            RingLayer.update(shape, with: ring, in: environment)
            CATransaction.commit()
        }
    }
}
#endif
