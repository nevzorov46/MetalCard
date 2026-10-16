import SwiftUI

/// The illustration a gift card wears instead of a plain colourway. Each one brings its
/// own ground and lettering, so a gift card looks the same whichever theme is chosen.
enum CardArt: String, Hashable, CaseIterable, Codable {
    case confetti, night, dusk

    var displayName: String {
        switch self {
        case .confetti: "Celebration"
        case .night:    "Night sky"
        case .dusk:     "Dusk"
        }
    }

    var base: Color {
        switch self {
        case .confetti: Color(hex: 0xF2EBDD)
        case .night:    Color(hex: 0x141A33)
        case .dusk:     Color(hex: 0x2A1D3E)
        }
    }

    var ink: Color {
        switch self {
        case .confetti: Color(hex: 0x1F1D1A)
        case .night:    Color(hex: 0xF1E9D2)
        case .dusk:     Color(hex: 0xF7E7EE)
        }
    }
}

/// Draws a `CardArt` to whatever size the card is. Every random choice comes from a fixed
/// seed, so the same card looks the same in the carousel, in the detail screen and after
/// a relaunch. The print sits on top: the name and number bottom-left, VISA bottom-right,
/// the label mid-left — the drawings keep those places quiet.
struct CardArtView: View {
    let art: CardArt

    var body: some View {
        Canvas { ctx, size in
            switch art {
            case .confetti: Self.confetti(ctx, size)
            case .night:    Self.night(ctx, size)
            case .dusk:     Self.dusk(ctx, size)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Confetti

    private static func confetti(_ ctx: GraphicsContext, _ s: CGSize) {
        var rng = Seeded(7)
        let u = s.width
        let colours: [Color] = [0x2A9D8F, 0xE07A8F, 0x2F3E75, 0xE9C46A, 0xA68DD4].map { Color(hex: $0) }

        var placed = 0, tries = 0
        while placed < 64, tries < 800 {
            tries += 1
            let x = CGFloat.random(in: 0...1, using: &rng)
            let y = CGFloat.random(in: 0...1, using: &rng)
            if y > 0.60 && x < 0.64 { continue }                  // name and number
            if y > 0.70 && x > 0.68 { continue }                  // VISA
            if y > 0.34 && y < 0.58 && x < 0.36 { continue }      // GIFT CARD
            if y < 0.22 && x > 0.84 { continue }                  // contactless
            placed += 1

            var c = ctx
            c.translateBy(x: x * s.width, y: y * s.height)
            c.rotate(by: .degrees(Double.random(in: 0...180, using: &rng)))
            let colour = colours[Int.random(in: 0..<colours.count, using: &rng)]

            switch Int.random(in: 0..<4, using: &rng) {
            case 0:
                let r = CGRect(x: -u * 0.019, y: -u * 0.0065, width: u * 0.038, height: u * 0.013)
                c.fill(Path(roundedRect: r, cornerRadius: u * 0.003), with: .color(colour))
            case 1:
                let r = u * CGFloat.random(in: 0.005...0.009, using: &rng)
                c.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)), with: .color(colour))
            case 2:
                let r = u * 0.010
                c.stroke(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)),
                         with: .color(colour), lineWidth: u * 0.0035)
            default:
                var path = Path()
                let length = u * 0.052
                path.move(to: CGPoint(x: -length / 2, y: 0))
                for i in 1...14 {
                    let t = CGFloat(i) / 14
                    path.addLine(to: CGPoint(x: -length / 2 + length * t, y: sin(t * .pi * 3) * u * 0.0075))
                }
                c.stroke(path, with: .color(colour),
                         style: StrokeStyle(lineWidth: u * 0.0042, lineCap: .round, lineJoin: .round))
            }
        }
    }

    // MARK: Night

    private static func night(_ ctx: GraphicsContext, _ s: CGSize) {
        var rng = Seeded(11)
        let w = s.width, h = s.height
        let cream = Color(hex: 0xF1E9D2)

        for _ in 0..<110 {
            let x = CGFloat.random(in: 0...1, using: &rng), y = CGFloat.random(in: 0...0.80, using: &rng)
            let r = w * CGFloat.random(in: 0.0016...0.0042, using: &rng)
            let o = Double.random(in: 0.25...0.9, using: &rng)
            if y > 0.58 && x < 0.50 { continue }                  // name and number
            if y > 0.34 && y < 0.58 && x < 0.38 { continue }      // GIFT CARD
            ctx.fill(Path(ellipseIn: circle(CGPoint(x: x * w, y: y * h), r)), with: .color(cream.opacity(o)))
        }

        // A few that twinkle: a dot with a thin cross.
        for _ in 0..<6 {
            let p = CGPoint(x: CGFloat.random(in: 0.4...0.95, using: &rng) * w,
                            y: CGFloat.random(in: 0.08...0.6, using: &rng) * h)
            let a = w * 0.014
            var cross = Path()
            cross.move(to: CGPoint(x: p.x - a, y: p.y)); cross.addLine(to: CGPoint(x: p.x + a, y: p.y))
            cross.move(to: CGPoint(x: p.x, y: p.y - a)); cross.addLine(to: CGPoint(x: p.x, y: p.y + a))
            ctx.stroke(cross, with: .color(cream.opacity(0.7)),
                       style: StrokeStyle(lineWidth: w * 0.0018, lineCap: .round))
            ctx.fill(Path(ellipseIn: circle(p, w * 0.0035)), with: .color(cream))
        }

        // A constellation in the corner the mark used to take.
        let stars = [(0.10, 0.13), (0.18, 0.20), (0.27, 0.15), (0.34, 0.25), (0.44, 0.19)]
            .map { CGPoint(x: $0.0 * w, y: $0.1 * h) }
        var line = Path()
        line.addLines(stars)
        ctx.stroke(line, with: .color(cream.opacity(0.30)), lineWidth: w * 0.0022)
        for p in stars { ctx.fill(Path(ellipseIn: circle(p, w * 0.0058)), with: .color(cream)) }

        // A crescent with a halo.
        let centre = CGPoint(x: 0.80 * w, y: 0.44 * h), r = w * 0.068
        ctx.fill(Path(ellipseIn: circle(centre, r * 2.4)),
                 with: .radialGradient(Gradient(colors: [cream.opacity(0.18), .clear]),
                                       center: centre, startRadius: 0, endRadius: r * 2.4))
        let moon = Path(ellipseIn: circle(centre, r))
            .subtracting(Path(ellipseIn: circle(CGPoint(x: centre.x + r * 0.46, y: centre.y - r * 0.24), r * 0.92)))
        ctx.fill(moon, with: .color(cream))

        // Two hills along the bottom, under the print.
        ctx.fill(hill(s, top: 0.79, amplitude: 0.05, frequency: 1.3, phase: 0.4), with: .color(Color(hex: 0x1F2849)))
        ctx.fill(hill(s, top: 0.88, amplitude: 0.04, frequency: 2.1, phase: 1.7), with: .color(Color(hex: 0x0D1226)))
    }

    // MARK: Dusk

    private static func dusk(_ ctx: GraphicsContext, _ s: CGSize) {
        let w = s.width, h = s.height
        let sun = CGPoint(x: 0.66 * w, y: 0.50 * h), r = w * 0.12

        ctx.fill(Path(CGRect(origin: .zero, size: s)),
                 with: .radialGradient(Gradient(colors: [Color(hex: 0xE8A3B8).opacity(0.42), .clear]),
                                       center: sun, startRadius: 0, endRadius: w * 0.56))
        ctx.fill(Path(ellipseIn: circle(sun, r)),
                 with: .linearGradient(Gradient(colors: [Color(hex: 0xF7D7DF), Color(hex: 0xE59DB3)]),
                                       startPoint: CGPoint(x: sun.x, y: sun.y - r),
                                       endPoint: CGPoint(x: sun.x, y: sun.y + r)))

        // Three birds against the glow.
        for (dx, dy, k) in [(-0.20, -0.20, 1.0), (-0.14, -0.25, 0.8), (-0.25, -0.13, 0.7)] {
            let p = CGPoint(x: sun.x + dx * w, y: sun.y + dy * h)
            let a = w * 0.014 * k
            var bird = Path()
            bird.move(to: CGPoint(x: p.x - a, y: p.y - a * 0.35))
            bird.addQuadCurve(to: p, control: CGPoint(x: p.x - a * 0.45, y: p.y - a * 0.55))
            bird.addQuadCurve(to: CGPoint(x: p.x + a, y: p.y - a * 0.35), control: CGPoint(x: p.x + a * 0.45, y: p.y - a * 0.55))
            ctx.stroke(bird, with: .color(Color(hex: 0x3A2853).opacity(0.75)),
                       style: StrokeStyle(lineWidth: w * 0.0028, lineCap: .round, lineJoin: .round))
        }

        // Ridges, far to near, each darker than the last.
        let ridges: [(top: CGFloat, amplitude: CGFloat, colour: UInt32, seed: UInt64)] = [
            (0.55, 0.11, 0x7A5598, 3), (0.64, 0.09, 0x553A78, 5),
            (0.74, 0.07, 0x38265A, 9), (0.84, 0.06, 0x1F1534, 13)
        ]
        for ridge in ridges {
            ctx.fill(mountains(s, top: ridge.top, amplitude: ridge.amplitude, seed: ridge.seed),
                     with: .color(Color(hex: ridge.colour)))
        }
    }

    // MARK: Shapes

    private static func circle(_ c: CGPoint, _ r: CGFloat) -> CGRect {
        CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
    }

    private static func hill(_ s: CGSize, top: CGFloat, amplitude: CGFloat, frequency: CGFloat, phase: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: s.height))
        for i in 0...60 {
            let t = CGFloat(i) / 60
            p.addLine(to: CGPoint(x: t * s.width,
                                  y: (top - amplitude * sin(t * .pi * frequency + phase)) * s.height))
        }
        p.addLine(to: CGPoint(x: s.width, y: s.height))
        p.closeSubpath()
        return p
    }

    /// Peaked rather than rolling: the absolute value of one sine makes the summits.
    private static func mountains(_ s: CGSize, top: CGFloat, amplitude: CGFloat, seed: UInt64) -> Path {
        var rng = Seeded(seed)
        let f1 = CGFloat.random(in: 2.2...3.4, using: &rng), p1 = CGFloat.random(in: 0...6, using: &rng)
        let f2 = CGFloat.random(in: 5...8, using: &rng), p2 = CGFloat.random(in: 0...6, using: &rng)
        let f3 = CGFloat.random(in: 11...16, using: &rng), p3 = CGFloat.random(in: 0...6, using: &rng)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: s.height))
        for i in 0...90 {
            let t = CGFloat(i) / 90
            let lift = abs(sin(t * f1 + p1)) * 0.65 + sin(t * f2 + p2) * 0.22 + sin(t * f3 + p3) * 0.08
            p.addLine(to: CGPoint(x: t * s.width, y: (top - amplitude * lift) * s.height))
        }
        p.addLine(to: CGPoint(x: s.width, y: s.height))
        p.closeSubpath()
        return p
    }
}

/// SplitMix64: small, fast, and the same sequence on every run.
private struct Seeded: RandomNumberGenerator {
    var state: UInt64
    init(_ seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
