import SwiftUI
import TimeBlockKit
#if os(macOS)
import AppKit

typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
#else
import UIKit

typealias PlatformColor = UIColor
typealias PlatformFont = UIFont

extension UIColor {
    /// The Mac's name for the text color, so the settings' text is the same color on either.
    static var labelColor: UIColor { .label }
}
#endif

extension RGB {
    /// `color` in sRGB, as a color picker gives it.
    init?(_ color: Color) {
        #if os(macOS)
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(r: srgb.redComponent, g: srgb.greenComponent, b: srgb.blueComponent)
        #else
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        // Extended sRGB, which goes past 0 and 1 for colors sRGB can't show.
        self.init(r: min(max(red, 0), 1), g: min(max(green, 0), 1), b: min(max(blue, 0), 1))
        #endif
    }
}

/// Whether there's an SF Symbol named `name`.
func symbolExists(_ name: String) -> Bool {
    #if os(macOS)
    NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    #else
    UIImage(systemName: name) != nil
    #endif
}

#if os(iOS)
/// Scrolls the settings to show what it's behind once it's on screen, as the Mac's does.
struct ScrollIntoView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { Probe() }
    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class Probe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            // Once the rows have laid out around it.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                var view = superview
                while let current = view, !(current is UIScrollView) { view = current.superview }
                guard let scrollView = view as? UIScrollView else { return }
                let frame = convert(bounds, to: scrollView).insetBy(dx: 0, dy: -8)
                scrollView.scrollRectToVisible(frame, animated: true)
            }
        }
    }
}
#endif

/// A picker sharing its row with other controls. On iOS a form's picker opens from a tap anywhere on its row, so
/// tapping the row's other labels opened it; there it's a menu holding the choices, which opens only from itself, as
/// a button takes only its own taps. On the Mac it's the picker.
struct RowPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    /// Each choice's name and value, in order.
    let options: [(name: String, value: Value)]

    var body: some View {
        #if os(iOS)
        LabeledContent(title) {
            Menu {
                picker
            } label: {
                HStack(spacing: 4) {
                    Text(options.first { $0.value == selection }?.name ?? "")
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                }
                // Gray, as a picker's: the menu's tint would make it the accent's.
                .foregroundStyle(Color.secondary)
            }
        }
        #else
        picker
        #endif
    }

    private var picker: some View {
        Picker(title, selection: $selection) {
            ForEach(options.indices, id: \.self) { index in
                Text(options[index].name).tag(options[index].value)
            }
        }
    }
}
