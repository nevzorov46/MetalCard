import SwiftUI

/// App palette, named by role rather than by hue, so a new accent is a change in one place.
enum Palette {
    static let ink = Color(hex: 0x100C1A)
    static let inkSecondary = Color(hex: 0x46425A)
    static let inkTertiary = Color(hex: 0x6F6B80)

    static let canvas = Color.white
    static let surface = Color(hex: 0xF2F0F7)

    /// Primary buttons, the avatar, active states. A light lavender, so text on it is dark.
    static let accent = Color(hex: 0xA898F0)
    static let onAccent = Color(hex: 0x1E1248)
    static let accentSoft = Color(hex: 0xEEEAFD)

    static let positive = Color(hex: 0x2E7D4F)

    static let iceSurface = Color(hex: 0xE3F1FB)
    static let iceInk = Color(hex: 0x0B4A73)
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

extension Font {
    /// Condensed black — the punchy face for balances and screen titles.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.condensed)
    }
}

extension Animation {
    /// Ice starts forming the moment you tap, then slows as it covers the card —
    /// a quick start reads as a response, a long finish lets the growth be seen.
    static let freeze = Animation.timingCurve(0.2, 0.15, 0.3, 1.0, duration: 2.6)
    /// Melting is quicker than freezing.
    static let thaw = Animation.easeIn(duration: 0.9)
}
