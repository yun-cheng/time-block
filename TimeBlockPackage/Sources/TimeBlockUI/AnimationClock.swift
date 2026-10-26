import SwiftUI

extension EnvironmentValues {
    /// Whether the day's animations and timers hold still: while its window can't be seen, or a menu over it is open.
    @Entry public var pausesAnimation = false
}

/// The clock an animated part of the day runs on, in seconds, at 15 fps: plenty for the pulse and horror effects. Only
/// what moves goes in one, so a frame draws just that again, not the whole day. Off, it stays at 0, a still frame.
struct AnimationClock<Content: View>: View {
    var isOn: Bool
    @ViewBuilder var content: (Double) -> Content
    @Environment(\.pausesAnimation) private var isPaused

    var body: some View {
        if isOn {
            TimelineView(.animation(minimumInterval: 1.0 / 15, paused: isPaused)) { context in
                content(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000))
            }
        } else {
            content(0)
        }
    }
}

/// The time each whole second, for the timers' times, until paused.
struct SecondClock<Content: View>: View {
    @ViewBuilder var content: (Date) -> Content
    @Environment(\.pausesAnimation) private var isPaused

    var body: some View {
        TimelineView(Seconds(isPaused: isPaused)) { context in
            content(context.date)
        }
    }

    private struct Seconds: TimelineSchedule {
        var isPaused: Bool

        func entries(from start: Date, mode: TimelineScheduleMode) -> some Sequence<Date> {
            let first = start.timeIntervalSinceReferenceDate.rounded(.down)
            return (0...).lazy.prefix(isPaused ? 1 : .max).map { Date(timeIntervalSinceReferenceDate: first + Double($0)) }
        }
    }
}
