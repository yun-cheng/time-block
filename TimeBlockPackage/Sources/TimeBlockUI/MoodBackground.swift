import SwiftUI
import TimeBlockKit

/// Gradient, then a closing vignette, scanlines and flicker as the night gets later.
public struct MoodBackground: View {
    let theme: MoodTheme
    var time: Double

    public init(theme: MoodTheme, time: Double = 0) {
        self.theme = theme
        self.time = time
    }

    public var body: some View {
        let mood = theme.mood
        ZStack {
            LinearGradient(colors: [theme.backgroundTop, theme.backgroundBottom], startPoint: .top, endPoint: .bottom)
            if mood >= .uneasy {
                GeometryReader { proxy in
                    RadialGradient(
                        colors: [.clear, .black.opacity(mood == .uneasy ? 0.45 : 0.75)],
                        center: .center, startRadius: 0,
                        endRadius: max(proxy.size.width, proxy.size.height) * 0.75)
                }
            }
            if mood == .nightmare {
                Canvas { context, size in
                    for y in stride(from: 0, to: size.height, by: 3) {
                        context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.white.opacity(0.035)))
                    }
                }
            }
            if time > 0, mood >= .dread, noise(Int(time * 12), 42) < (mood == .nightmare ? 0.08 : 0.04) {
                Color.black.opacity(0.35)
            }
        }
    }
}
