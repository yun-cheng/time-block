import SwiftUI
import TimeBlockKit

extension Color {
    public init(rgb: RGB, opacity: Double = 1) {
        self.init(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: opacity)
    }

    init(hex: UInt32, opacity: Double = 1) {
        self.init(rgb: RGB(hex: hex), opacity: opacity)
    }
}

/// How a block is filled.
public enum CellPaint {
    case solid(Color)
    /// A future block with something pre-logged; calendar events are dashed.
    case planned(Color, dashed: Bool)
    case empty(Color)
}

/// Colors for one mood. Calm moods follow light/dark mode; past bedtime it is always dark.
public struct MoodTheme: Sendable {
    public let mood: Mood
    public let backgroundTop: Color
    public let backgroundBottom: Color
    public let text: Color
    public let secondaryText: Color
    /// Counter color and highlights.
    public let accent: Color
    public let emptyBlock: Color
    public let unloggedBlock: Color
    public let overtimeBlock: Color
    /// A block set aside to wind down with nothing planned, and one that went unlogged.
    public let windDownEmptyBlock: Color
    public let windDownUnloggedBlock: Color

    /// The hue of winding down: the warm light before bed.
    static let windDownHue = Color(hex: 0xF59E0B)

    public init(mood: Mood, colorScheme: ColorScheme) {
        self.mood = mood
        switch mood {
        case .calm, .windDown:
            let warm = mood == .windDown
            if colorScheme == .dark {
                backgroundTop = Color(hex: warm ? 0x2B2017 : 0x1D1F24)
                backgroundBottom = Color(hex: warm ? 0x17110C : 0x121317)
                text = .white.opacity(0.93)
                secondaryText = .white.opacity(0.55)
                emptyBlock = .white.opacity(0.09)
                unloggedBlock = .white.opacity(0.24)
            } else {
                backgroundTop = Color(hex: warm ? 0xFFF3E2 : 0xFAFAF8)
                backgroundBottom = Color(hex: warm ? 0xF5E1C8 : 0xEDEDE9)
                text = .black.opacity(0.88)
                secondaryText = .black.opacity(0.5)
                emptyBlock = .black.opacity(0.07)
                unloggedBlock = .black.opacity(0.2)
            }
            accent = warm ? Self.windDownHue : text
            overtimeBlock = Color(hex: 0xC0182A)
            windDownEmptyBlock = Self.windDownHue.opacity(colorScheme == .dark ? 0.2 : 0.22)
            windDownUnloggedBlock = Self.windDownHue.opacity(0.5)
        case .uneasy:
            backgroundTop = Color(hex: 0x241518)
            backgroundBottom = Color(hex: 0x0F0A0B)
            text = Color(hex: 0xF3DADA)
            secondaryText = Color(hex: 0xF3DADA, opacity: 0.55)
            accent = Color(hex: 0xFF4D4D)
            emptyBlock = .white.opacity(0.07)
            unloggedBlock = Color(hex: 0x5A3A3D)
            overtimeBlock = Color(hex: 0xB0303C)
            // Past bedtime, the time to wind down has gone by like the rest.
            windDownEmptyBlock = emptyBlock
            windDownUnloggedBlock = unloggedBlock
        case .dread:
            backgroundTop = Color(hex: 0x2E0609)
            backgroundBottom = Color(hex: 0x0B0203)
            text = Color(hex: 0xFFC7C7)
            secondaryText = Color(hex: 0xFFC7C7, opacity: 0.5)
            accent = Color(hex: 0xFF2E2E)
            emptyBlock = Color(hex: 0xFF2E2E, opacity: 0.1)
            unloggedBlock = Color(hex: 0x4A1C1F)
            overtimeBlock = Color(hex: 0xC8142A)
            windDownEmptyBlock = emptyBlock
            windDownUnloggedBlock = unloggedBlock
        case .nightmare:
            backgroundTop = Color(hex: 0x170000)
            backgroundBottom = .black
            text = Color(hex: 0xFF3B3B)
            secondaryText = Color(hex: 0xFF3B3B, opacity: 0.5)
            accent = Color(hex: 0xFF1A1A)
            emptyBlock = Color(hex: 0xFF1A1A, opacity: 0.08)
            unloggedBlock = Color(hex: 0x3A0A0D)
            overtimeBlock = Color(hex: 0xE0101E)
            windDownEmptyBlock = emptyBlock
            windDownUnloggedBlock = unloggedBlock
        }
    }

    /// Category colors drain toward blood red the later it gets.
    public func grade(_ color: RGB) -> RGB {
        switch mood {
        case .calm, .windDown: color
        case .uneasy: color.desaturated(0.55).mixed(with: RGB(hex: 0x2A1416), amount: 0.25)
        case .dread: color.desaturated(0.7).mixed(with: RGB(hex: 0x7A0A10), amount: 0.55)
        case .nightmare: color.desaturated(0.9).mixed(with: RGB(hex: 0x3A0004), amount: 0.75)
        }
    }

    public func color(of category: BlockCategory) -> Color {
        Color(rgb: grade(category.color))
    }

    public func paint(for cell: BlockCell, categories: [String: BlockCategory]) -> CellPaint {
        if cell.isOvertime && cell.phase != .future { return .solid(overtimeBlock) }
        let category = cell.categoryID.flatMap { categories[$0] }
        switch cell.phase {
        case .past, .current:
            if let category { return .solid(color(of: category)) }
            if cell.phase == .current { return .solid(accent.opacity(0.85)) }
            return .solid(cell.isWindDown ? windDownUnloggedBlock : unloggedBlock)
        case .future:
            if let category { return .planned(color(of: category), dashed: cell.source == .calendar) }
            return .empty(cell.isWindDown ? windDownEmptyBlock : emptyBlock)
        }
    }
}

public enum MoodCopy {
    public static func caption(_ mood: Mood) -> String {
        switch mood {
        case .calm: "blocks left"
        case .windDown: "blocks until bed"
        case .uneasy: "blocks past bedtime"
        case .dread: "borrowed from tomorrow"
        case .nightmare: "stolen from tomorrow"
        }
    }

    public static func line(_ mood: Mood) -> String? {
        switch mood {
        case .calm: nil
        case .windDown: "Start winding down."
        case .uneasy: "It's past your bedtime."
        case .dread: "Every block now comes out of tomorrow."
        case .nightmare: "You are not getting these back. Go to sleep."
        }
    }
}

/// Stable pseudo-random value in 0..<1, so horror effects land on the same blocks every render.
func noise(_ a: Int, _ b: Int = 0) -> Double {
    var x = UInt64(bitPattern: Int64((a &* 73_856_093) ^ (b &* 19_349_663))) &+ 0x9E37_79B9_7F4A_7C15
    x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
    x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
    x ^= x >> 31
    return Double(x >> 11) / Double(UInt64(1) << 53)
}
