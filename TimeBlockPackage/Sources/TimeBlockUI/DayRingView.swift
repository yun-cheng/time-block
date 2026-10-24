import SwiftUI
import TimeBlockKit

/// The waking day as one ring of blocks. Blocks past bedtime wind onto inner rings, like debt piling up.
public struct DayRingView: View {
    let snapshot: DaySnapshot
    let theme: MoodTheme

    public init(snapshot: DaySnapshot, theme: MoodTheme) {
        self.snapshot = snapshot
        self.theme = theme
    }

    public var body: some View {
        Canvas { context, size in
            let awake = snapshot.status.schedule.awakeBlocks
            guard awake > 0 else { return }
            let diameter = min(size.width, size.height)
            let width = diameter * 0.075
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = diameter / 2 - width
            let step = 2 * Double.pi / Double(awake)
            let gap = step * 0.22

            for cell in snapshot.cells {
                let lap = cell.index / awake
                let radius = outer - CGFloat(lap) * width * 1.6
                guard radius > width else { continue }
                let start = -Double.pi / 2 + Double(cell.index % awake) * step + gap / 2
                var arc = Path()
                arc.addArc(
                    center: center, radius: radius, startAngle: .radians(start),
                    endAngle: .radians(start + step - gap), clockwise: false)
                let color: Color
                switch theme.paint(for: cell, categories: snapshot.categories) {
                case .solid(let c): color = c
                case .planned(let c, _): color = c.opacity(0.45)
                case .empty(let c): color = c
                }
                let isCurrent = cell.phase == .current
                context.stroke(arc, with: .color(isCurrent ? theme.text : color), lineWidth: isCurrent ? width * 1.7 : width)
            }
        }
    }
}
