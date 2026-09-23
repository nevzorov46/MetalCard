import SwiftUI

/// App palette. Each card colourway is a bright tone paired with a dark ink.
enum Palette {
    static let ink = Color(hex: 0x0E0F0C)
    static let inkSecondary = Color(hex: 0x454745)
    static let inkTertiary = Color(hex: 0x6A6C6A)

    static let canvas = Color.white
    static let surface = Color(hex: 0xF0F2EC)

    static let lime = Color(hex: 0x9FE870)
    static let forest = Color(hex: 0x163300)
    static let positive = Color(hex: 0x2F5711)

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
    /// Ice creeps in slowly, picks up speed, then settles — so the whole growth is visible.
    static let freeze = Animation.easeInOut(duration: 2.8)
    /// Melting is quicker than freezing.
    static let thaw = Animation.easeIn(duration: 0.9)
}
