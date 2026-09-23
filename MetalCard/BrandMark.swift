import SwiftUI

/// Placeholder brand: a leaf glyph and a lowercase wordmark. Change `name` to rebrand.
enum Brand {
    static let name = "fern"
}

/// A leaf lying on the diagonal. With `vein`, the vein is cut out (fill it with `eoFill`).
struct LeafShape: Shape {
    var vein = true

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - s / 2, y: rect.midY - s / 2)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * s, y: origin.y + y * s) }

        var path = Path()
        path.move(to: p(0.06, 0.94))
        path.addQuadCurve(to: p(0.94, 0.06), control: p(0.02, 0.02))
        path.addQuadCurve(to: p(0.06, 0.94), control: p(0.98, 0.98))
        path.closeSubpath()
        guard vein else { return path }

        // Vein: a thin quad along the diagonal. Even-odd fill turns it into a gap.
        let t = 0.03 * s / sqrt(2)
        let a = p(0.24, 0.76), b = p(0.70, 0.30)
        path.addLines([
            CGPoint(x: a.x - t, y: a.y - t), CGPoint(x: b.x - t, y: b.y - t),
            CGPoint(x: b.x + t, y: b.y + t), CGPoint(x: a.x + t, y: a.y + t)
        ])
        path.closeSubpath()
        return path
    }
}

struct BrandMark: View {
    var size: CGFloat
    var color: Color

    var body: some View {
        HStack(spacing: size * 0.22) {
            LeafShape()
                .fill(color, style: FillStyle(eoFill: true))
                .frame(width: size * 0.95, height: size * 0.95)
            Text(Brand.name)
                .font(.system(size: size, weight: .black))
                .tracking(-size * 0.03)
                .foregroundStyle(color)
        }
    }
}
