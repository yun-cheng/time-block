import SwiftUI
import TimeBlockKit

/// The day as rows of clock hours, 12 five-minute blocks per row.
/// A wake time of 08:30 starts halfway along the "08" row.
public struct BlockGridView: View {
    let snapshot: DaySnapshot
    let theme: MoodTheme
    /// Hour rows to show; nil shows the whole day.
    var rows: Range<Int>?
    var showsHourLabels: Bool
    /// Animation clock in seconds. 0 draws a still frame, which is all a widget can show.
    var time: Double

    public init(
        snapshot: DaySnapshot, theme: MoodTheme, rows: Range<Int>? = nil,
        showsHourLabels: Bool = true, time: Double = 0
    ) {
        self.snapshot = snapshot
        self.theme = theme
        self.rows = rows
        self.showsHourLabels = showsHourLabels
        self.time = time
    }

    public static func rowCount(for snapshot: DaySnapshot) -> Int {
        let slots = snapshot.status.schedule.gridOffset + snapshot.cells.count
        return (slots + Schedule.blocksPerHour - 1) / Schedule.blocksPerHour
    }

    /// `count` rows around the current hour, for widgets too small for the whole day.
    public static func rows(around snapshot: DaySnapshot, count: Int) -> Range<Int> {
        let total = rowCount(for: snapshot)
        let slot = (snapshot.status.currentIndex ?? 0) + snapshot.status.schedule.gridOffset
        let current = min(slot / Schedule.blocksPerHour, total - 1)
        let start = max(0, min(current - count / 2, total - count))
        return start..<min(total, start + count)
    }

    public var body: some View {
        Canvas { context, size in draw(in: &context, size: size) }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let perRow = Schedule.blocksPerHour
        let rows = self.rows ?? 0..<Self.rowCount(for: snapshot)
        guard !rows.isEmpty else { return }

        let mood = snapshot.mood
        let animated = time > 0
        let tick = Int(time * 9)
        let gapRatio: CGFloat = 0.24
        let labelWidth: CGFloat = showsHourLabels ? 24 : 0
        let columns = CGFloat(perRow)
        let rowCount = CGFloat(rows.count)
        let side = min(
            (size.width - labelWidth) / (columns + (columns - 1) * gapRatio),
            size.height / (rowCount + (rowCount - 1) * gapRatio))
        let gap = side * gapRatio
        let radius = side * 0.28
        let gridWidth = columns * side + (columns - 1) * gap
        let originX = labelWidth + (size.width - labelWidth - gridWidth) / 2
        let schedule = snapshot.status.schedule
        let awake = schedule.awakeBlocks
        let offset = schedule.gridOffset
        let visible = snapshot.cells.filter { rows.contains(($0.index + offset) / perRow) }

        func frame(_ index: Int) -> CGRect {
            let slot = index + offset
            let row = slot / perRow - rows.lowerBound
            let column = slot % perRow
            return CGRect(
                x: originX + CGFloat(column) * (side + gap), y: CGFloat(row) * (side + gap),
                width: side, height: side)
        }

        if showsHourLabels {
            let fontSize = min(11, max(7, side * 0.8))
            for row in rows {
                let first = row * perRow - offset
                let text = Text(String(format: "%02d", schedule.hour(ofRow: row)))
                    .font(.system(size: fontSize, weight: .medium, design: mood >= .uneasy ? .monospaced : .rounded))
                    .foregroundColor(first >= awake ? theme.accent : theme.secondaryText)
                let y = CGFloat(row - rows.lowerBound) * (side + gap) + side / 2
                context.draw(text, at: CGPoint(x: originX - 6, y: y), anchor: .trailing)
            }
        }

        for cell in visible {
            var rect = frame(cell.index)
            var angle = 0.0
            if mood == .nightmare && cell.phase != .future {
                // A few blocks twitch when animated; the rest just sit crooked.
                let seed = animated && noise(cell.index, 99) < 0.15 ? tick : 0
                rect = rect.offsetBy(
                    dx: (noise(cell.index, 1 + seed) - 0.5) * side * 0.3,
                    dy: (noise(cell.index, 2 + seed) - 0.5) * side * 0.3)
                angle = (noise(cell.index, 3 + seed) - 0.5) * 0.5
            }
            let path = Path(roundedRect: rect, cornerRadius: radius)
                .rotated(by: angle, around: CGPoint(x: rect.midX, y: rect.midY))

            switch theme.paint(for: cell, categories: snapshot.categories) {
            case .solid(let color):
                if mood == .nightmare && cell.phase == .past && noise(cell.index, 5) < 0.1 {
                    // Dead block: only the outline is left.
                    context.stroke(path, with: .color(color.opacity(0.6)), lineWidth: max(1, side * 0.08))
                } else {
                    context.fill(path, with: .color(color))
                }
            case .planned(let color, let dashed):
                let line = max(1, side * 0.1)
                context.fill(path, with: .color(color.opacity(0.18)))
                context.stroke(
                    Path(roundedRect: rect.insetBy(dx: line / 2, dy: line / 2), cornerRadius: radius),
                    with: .color(color.opacity(0.9)),
                    style: StrokeStyle(lineWidth: line, dash: dashed ? [line * 1.6, line * 1.2] : []))
            case .empty(let color):
                context.fill(path, with: .color(color))
            }

            if cell.phase == .current {
                let pulse = animated ? 0.55 + 0.45 * sin(time * 4) : 1
                let ring = frame(cell.index).insetBy(dx: -gap * 0.55, dy: -gap * 0.55)
                context.stroke(
                    Path(roundedRect: ring, cornerRadius: radius + gap * 0.55),
                    with: .color(theme.text.opacity(pulse)), lineWidth: max(1, gap * 0.45))
            }
        }

        if mood >= .dread {
            drawDrips(in: &context, cells: visible, side: side, radius: radius, animated: animated, frame: frame)
        }

        // Bedtime line, once the day has spilled past it. Steps around a bedtime that isn't on the hour.
        let boundary = awake + offset
        let boundaryRow = boundary / perRow
        if snapshot.status.overtimeBlocks > 0, rows.contains(boundaryRow) {
            let column = boundary % perRow
            let top = CGFloat(boundaryRow - rows.lowerBound) * (side + gap) - gap / 2
            let bottom = top + side + gap
            let x = originX + CGFloat(column) * (side + gap) - gap / 2
            let left = originX - 2
            let right = originX + gridWidth + 2
            let spillsToNextRow = boundary + snapshot.status.overtimeBlocks > (boundaryRow + 1) * perRow
            var line = Path()
            if column == 0 {
                line.move(to: CGPoint(x: left, y: top))
            } else {
                if spillsToNextRow {
                    line.move(to: CGPoint(x: left, y: bottom))
                    line.addLine(to: CGPoint(x: x, y: bottom))
                } else {
                    line.move(to: CGPoint(x: x, y: bottom))
                }
                line.addLine(to: CGPoint(x: x, y: top))
            }
            line.addLine(to: CGPoint(x: right, y: top))
            context.stroke(line, with: .color(theme.accent.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    private func drawDrips(
        in context: inout GraphicsContext, cells: [BlockCell], side: CGFloat, radius: CGFloat,
        animated: Bool, frame: (Int) -> CGRect
    ) {
        let nightmare = snapshot.mood == .nightmare
        for cell in cells where cell.phase != .future && noise(cell.index, 7) < (nightmare ? 0.3 : 0.16) {
            guard case .solid(let color) = theme.paint(for: cell, categories: snapshot.categories) else { continue }
            let rect = frame(cell.index)
            let reach = side * (nightmare ? 2.4 : 1.3) * (0.35 + 0.65 * noise(cell.index, 8))
            let growth = animated ? 0.85 + 0.15 * sin(time * 0.8 + noise(cell.index, 9) * 6) : 1
            let width = side * (0.16 + 0.12 * noise(cell.index, 10))
            let x = rect.minX + rect.width * (0.25 + 0.5 * noise(cell.index, 11)) - width / 2
            let stem = CGRect(x: x, y: rect.maxY - radius, width: width, height: reach * growth + radius)
            context.fill(Path(roundedRect: stem, cornerRadius: width / 2), with: .color(color))
            let drop = width * 1.5
            context.fill(
                Path(ellipseIn: CGRect(x: x + width / 2 - drop / 2, y: stem.maxY - drop * 0.8, width: drop, height: drop * 1.15)),
                with: .color(color))
        }
    }
}

extension Path {
    fileprivate func rotated(by angle: Double, around center: CGPoint) -> Path {
        guard angle != 0 else { return self }
        return applying(
            CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: angle)
                .translatedBy(x: -center.x, y: -center.y))
    }
}
