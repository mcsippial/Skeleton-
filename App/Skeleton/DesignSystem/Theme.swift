import SwiftUI

/// Design tokens from CLAUDE.md §12. The 3D body is the hero; the UI stays quiet.
enum Theme {
    enum Color {
        static let background = SwiftUI.Color(hex: 0xF4F4F6)
        static let text = SwiftUI.Color(hex: 0x0B0B0C)
        static let secondaryText = SwiftUI.Color(hex: 0x6E6E76)
        static let hairline = SwiftUI.Color.black.opacity(0.08)
        static let track = SwiftUI.Color.black.opacity(0.05)

        // Colour is reserved for meaning.
        static let pain = SwiftUI.Color(hex: 0xFF4D3D)
        static let nerves = SwiftUI.Color(hex: 0xF5C542)
        static let muscles = SwiftUI.Color(hex: 0xC2453F)
        static let bones = SwiftUI.Color(hex: 0xE9E1CC)
        static let tendons = SwiftUI.Color(hex: 0xF2EFE6)
        static let redFlag = SwiftUI.Color(hex: 0xA3241A)

        /// Pain colour by intensity 0–10: amber at the low end, red at the top.
        static func pain(intensity: Int) -> SwiftUI.Color {
            let k = Double(min(max(intensity, 0), 10)) / 10
            return SwiftUI.Color(hue: 0.11 - k * 0.11, saturation: 1, brightness: 1)
        }

        /// Iridescent sequence for rainbow glass borders: pink → amber → mint → sky → violet.
        static let iridescent: [SwiftUI.Color] = [
            SwiftUI.Color(hex: 0xFF8A8A), SwiftUI.Color(hex: 0xFFD27A), SwiftUI.Color(hex: 0x9FF0B8),
            SwiftUI.Color(hex: 0x7FD6FF), SwiftUI.Color(hex: 0xB79CFF), SwiftUI.Color(hex: 0xFF9EE5),
            SwiftUI.Color(hex: 0xFF8A8A),
        ]
    }

    enum Radius {
        static let small: CGFloat = 14
        static let medium: CGFloat = 22
        static let large: CGFloat = 28
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 14
        static let l: CGFloat = 20
        static let xl: CGFloat = 28
    }

    enum Font {
        static let largeTitle = SwiftUI.Font.system(size: 30, weight: .bold)
        static let title = SwiftUI.Font.system(size: 22, weight: .bold)
        static let headline = SwiftUI.Font.system(size: 17, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 15)
        static let callout = SwiftUI.Font.system(size: 13.5)
        static let caption = SwiftUI.Font.system(size: 12)
        static let label = SwiftUI.Font.system(size: 11, weight: .bold)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension View {
    /// Large bold title with tight tracking.
    func titleStyle() -> some View {
        font(Theme.Font.largeTitle).tracking(-0.6).foregroundStyle(Theme.Color.text)
    }
}
