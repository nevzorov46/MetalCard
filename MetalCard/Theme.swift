import SwiftUI

/// A complete look: neutrals, the accent, the ice colours and four card colourways.
/// Views read it from the environment, so switching themes restyles the whole app at once.
struct Theme: Identifiable, Equatable {
    struct Colourway: Equatable {
        var base: Color
        var ink: Color
    }

    let id: String
    let name: String
    var isDark = false

    var ink: Color
    var inkSecondary: Color
    var inkTertiary: Color
    var canvas: Color
    var surface: Color

    /// Primary buttons, the avatar, active states.
    var accent: Color
    var onAccent: Color
    var accentSoft: Color

    var positive: Color
    var iceSurface: Color
    var iceInk: Color

    var primary: Colourway
    var metal: Colourway
    var secondary: Colourway
    var tertiary: Colourway

    func colourway(_ style: Card.Style) -> Colourway {
        switch style {
        case .primary: primary
        case .metal: metal
        case .secondary: secondary
        case .tertiary: tertiary
        }
    }
}

// MARK: - Presets

extension Theme {
    static let all: [Theme] = [.lavender, .tangerine, .rose, .cobalt, .saffron, .graphite]

    static func named(_ id: String) -> Theme { all.first { $0.id == id } ?? .lavender }

    static let lavender = light(id: "lavender", name: "Lavender", surface: 0xF2F0F7,
                                accent: 0xA898F0, onAccent: 0x1E1248, accentSoft: 0xEEEAFD,
                                primary: (0xA898F0, 0x1E1248), metal: (0x1E1830, 0xCFC4FF),
                                secondary: (0xFFCFB0, 0x3F1C0B), tertiary: (0xFFE7A0, 0x2E2200))

    static let tangerine = light(id: "tangerine", name: "Tangerine", surface: 0xF6F1EC,
                                 accent: 0xFF8A3D, onAccent: 0x3A1300, accentSoft: 0xFFEBDD,
                                 primary: (0xFF8A3D, 0x3A1300), metal: (0x221A15, 0xFFB88A),
                                 secondary: (0xF3DDC3, 0x3B2A16), tertiary: (0xD9CCFF, 0x2A1466))

    static let rose = light(id: "rose", name: "Rose", surface: 0xF7F0F2,
                            accent: 0xFF8FA3, onAccent: 0x4A0F1E, accentSoft: 0xFFE6EB,
                            primary: (0xFF8FA3, 0x4A0F1E), metal: (0x2A151D, 0xFFB3C1),
                            secondary: (0xFFF0D9, 0x4A2E0A), tertiary: (0xCFE3FF, 0x0F2A55))

    static let cobalt = light(id: "cobalt", name: "Cobalt", surface: 0xEFF2F8,
                              accent: 0x7B96FF, onAccent: 0x0E1A4D, accentSoft: 0xE4EAFF,
                              primary: (0x7B96FF, 0x0E1A4D), metal: (0x111A33, 0xA9BCFF),
                              secondary: (0xFFD9B8, 0x3F1C0B), tertiary: (0xE2D8FF, 0x2A1466))

    static let saffron = light(id: "saffron", name: "Saffron", surface: 0xF5F3EA,
                               accent: 0xF5C542, onAccent: 0x2A2000, accentSoft: 0xFDF1CC,
                               primary: (0xF5C542, 0x2A2000), metal: (0x151515, 0xF5C542),
                               secondary: (0xF1E9D6, 0x3A2F16), tertiary: (0xD9CCFF, 0x2A1466))

    /// The dark one: graphite, copper and titanium.
    static let graphite = Theme(
        id: "graphite", name: "Graphite", isDark: true,
        ink: Color(hex: 0xF2F0EB), inkSecondary: Color(hex: 0xB8B4AC), inkTertiary: Color(hex: 0x8C8880),
        canvas: Color(hex: 0x111214), surface: Color(hex: 0x1E1F22),
        accent: Color(hex: 0xD9905E), onAccent: Color(hex: 0x1F0F05), accentSoft: Color(hex: 0x3A2A20),
        positive: Color(hex: 0x6FCF97), iceSurface: Color(hex: 0x16283A), iceInk: Color(hex: 0xA8D8FF),
        primary: .init(base: Color(hex: 0xD9905E), ink: Color(hex: 0x1F0F05)),
        metal: .init(base: Color(hex: 0x2A2B2F), ink: Color(hex: 0xE9B98F)),
        secondary: .init(base: Color(hex: 0xCFCBC3), ink: Color(hex: 0x262422)),
        tertiary: .init(base: Color(hex: 0x0B0B0C), ink: Color(hex: 0xD9905E)))

    /// Light themes share their neutrals; the surface is tinted towards the accent.
    private static func light(id: String, name: String, surface: UInt32,
                              accent: UInt32, onAccent: UInt32, accentSoft: UInt32,
                              primary: (UInt32, UInt32), metal: (UInt32, UInt32),
                              secondary: (UInt32, UInt32), tertiary: (UInt32, UInt32)) -> Theme {
        func way(_ pair: (UInt32, UInt32)) -> Colourway { .init(base: Color(hex: pair.0), ink: Color(hex: pair.1)) }
        return Theme(
            id: id, name: name,
            ink: Color(hex: 0x121116), inkSecondary: Color(hex: 0x48465A), inkTertiary: Color(hex: 0x716E80),
            canvas: .white, surface: Color(hex: surface),
            accent: Color(hex: accent), onAccent: Color(hex: onAccent), accentSoft: Color(hex: accentSoft),
            positive: Color(hex: 0x2E7D4F), iceSurface: Color(hex: 0xE3F1FB), iceInk: Color(hex: 0x0B4A73),
            primary: way(primary), metal: way(metal), secondary: way(secondary), tertiary: way(tertiary))
    }
}

extension EnvironmentValues {
    @Entry var theme: Theme = .lavender
}

/// Which theme is chosen. Kept across launches.
@Observable
final class Appearance {
    var themeID: String {
        didSet { UserDefaults.standard.set(themeID, forKey: Self.key) }
    }

    var theme: Theme { Theme.named(themeID) }

    private static let key = "theme"

    init() {
        themeID = UserDefaults.standard.string(forKey: Self.key) ?? Theme.lavender.id
        #if DEBUG
        // `-theme <id>` starts in that theme, for screenshots.
        let arguments = ProcessInfo.processInfo.arguments
        if let i = arguments.firstIndex(of: "-theme"), i + 1 < arguments.count {
            themeID = arguments[i + 1]
        }
        #endif
    }
}

// MARK: - Helpers

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
