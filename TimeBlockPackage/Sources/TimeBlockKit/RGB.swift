/// A platform-neutral color, so the model layer can grade colors without SwiftUI.
public struct RGB: Hashable, Codable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    public var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    public func mixed(with other: RGB, amount t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    public func desaturated(_ amount: Double) -> RGB {
        let l = luminance
        return mixed(with: RGB(r: l, g: l, b: l), amount: amount)
    }
}
