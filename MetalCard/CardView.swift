import SwiftUI

/// The card face. Every size is a fraction of the card's width, so the same view
/// looks identical in the carousel, in the detail screen and in the middle of the zoom.
struct CardView: View {
    static let aspect: CGFloat = 1.586       // ISO/IEC 7810 ID-1, same as a real card
    static let cornerRatio: CGFloat = 0.055

    let card: Card
    var tilt: CGSize = .zero
    var frost: Double = 0                   // 0...1, animatable
    var showsDetails = false
    var lift: CGFloat = 0                   // 0...1, how far the card is picked up

    var body: some View {
        TimelineView(.animation(paused: frost == 0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000)
            GeometryReader { geo in
                let w = geo.size.width
                face(width: w)
                    .modifier(FrostEffect(progress: frost, tilt: tilt, time: time))
                    .overlay(alignment: .topTrailing) { frozenBadge(width: w) }
            }
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
        // A soft glow in the card's own colour, plus a short dark contact shadow. Deriving the
        // glow from the base (not the ink) keeps it dark under cards with light lettering.
        // The light is overhead, so the shadow slides away from the tilt, and a card that is
        // picked up casts a longer, softer one.
        .shadow(color: card.base.opacity(0.40 - lift * 0.08),
                radius: 20 + lift * 14,
                x: -tilt.width * 10,
                y: 14 + lift * 12 - tilt.height * 6)
        .shadow(color: .black.opacity(0.10 - lift * 0.04),
                radius: 3 + lift * 4,
                x: -tilt.width * 2,
                y: 2 + lift * 4)
    }

    // MARK: Face

    // Built as overlays on the base fill: overlays never change the size of what they sit on,
    // so the oversized decorative leaf can't push the layout around.
    private func face(width w: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: w * Self.cornerRatio, style: .continuous)
        let t = tilt
        let glare = Float(lift)
        let strength: Float = card.finish == .metal ? 0.55 : 0.14
        // Parallax: the print sits "above" the plastic and the leaf "below" it, so they drift
        // apart as the card turns.
        let print = CGSize(width: tilt.width * w * 0.010, height: tilt.height * w * 0.010)
        let under = CGSize(width: -tilt.width * w * 0.022, height: -tilt.height * w * 0.022)
        // The rim catches the light on the side the card is turned towards.
        let rimFrom = UnitPoint(x: 0.5 - tilt.width * 0.5, y: -tilt.height * 0.5)
        let rimTo = UnitPoint(x: 0.5 + tilt.width * 0.5, y: 1 + tilt.height * 0.5)

        return shape
            .fill(card.base)
            // Gentle light falloff, so the plastic reads as a physical object.
            .overlay(
                shape.fill(LinearGradient(colors: [.white.opacity(0.10), .clear, .black.opacity(0.08)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            // An oversized leaf, tone on tone, sweeping off the right edge.
            .overlay(alignment: .topLeading) {
                LeafShape(vein: false)
                    .fill(card.ink.opacity(0.08))
                    .frame(width: w * 1.05, height: w * 1.05)
                    .offset(x: w * 0.42 + under.width, y: -w * 0.10 + under.height)
            }
            .overlay(
                Rectangle()
                    .fill(.white)
                    .colorEffect(ShaderLibrary.grain(.float(card.finish == .metal ? 0.24 : 0.10),
                                                     .float(card.finish == .metal ? 1 : 0)))
                    .blendMode(.overlay)
            )
            .overlay(content(width: w).offset(print))
            .overlay(
                Rectangle()
                    .fill(.white)
                    .visualEffect { view, proxy in
                        view.colorEffect(ShaderLibrary.sheen(.float2(proxy.size), .float2(t),
                                                             .float(strength), .float(glare)))
                    }
                    .blendMode(.plusLighter)
            )
            .overlay(
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.45 + lift * 0.2),
                                                           .white.opacity(0.05), .clear],
                                                  startPoint: rimFrom, endPoint: rimTo),
                                   lineWidth: 1)
            )
            .frame(width: w, height: w / Self.aspect)
            .compositingGroup()
            .clipShape(shape)
    }

    private func content(width w: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                BrandMark(size: w * 0.068, color: card.ink)
                Spacer()
                Image(systemName: "wave.3.right")
                    .font(.system(size: w * 0.052, weight: .semibold))
                    .opacity(0.75)
            }

            Spacer(minLength: 0)

            if card.isVirtual {
                Text("VIRTUAL")
                    .font(.system(size: w * 0.032, weight: .bold))
                    .tracking(w * 0.006)
                    .padding(.horizontal, w * 0.025)
                    .padding(.vertical, w * 0.012)
                    .overlay(Capsule().strokeBorder(card.ink.opacity(0.5), lineWidth: 1))
            } else {
                ChipView(width: w * 0.125)
            }

            Spacer(minLength: 0)

            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: w * 0.01) {
                    Text(showsDetails ? "VALID \(card.expiry)    CVV \(card.cvv)" : card.name)
                        .font(.system(size: w * 0.036, weight: .semibold).monospacedDigit())
                        .opacity(0.8)
                    Text(showsDetails ? card.groupedNumber : "•• \(card.last4)")
                        .font(.system(size: w * 0.056, weight: .semibold).monospacedDigit())
                }
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.5), value: showsDetails)

                Spacer(minLength: 0)

                Text("VISA")
                    .font(.system(size: w * 0.072, weight: .heavy))
                    .italic()
            }
        }
        .foregroundStyle(card.ink)
        .padding(w * 0.064)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Frozen badge

    private func frozenBadge(width w: CGFloat) -> some View {
        ZStack {
            if frost > 0.5 {
                HStack(spacing: w * 0.015) {
                    Image(systemName: "snowflake")
                    Text("Frozen")
                }
                .font(.system(size: w * 0.036, weight: .bold))
                .foregroundStyle(Palette.iceInk)
                .padding(.horizontal, w * 0.032)
                .padding(.vertical, w * 0.017)
                .background(.white.opacity(0.92), in: Capsule())
                .padding(w * 0.05)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.7).delay(frost > 0.5 ? 1.6 : 0),
                   value: frost > 0.5)
    }
}

// MARK: - Frost

/// Animatable, so a plain `withAnimation` on the frozen flag drives the shader's
/// progress frame by frame instead of jumping from 0 to 1.
struct FrostEffect: ViewModifier, Animatable {
    var progress: Double
    var tilt: CGSize
    var time: Double

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = Float(progress), t = tilt, tm = Float(time)
        content.visualEffect { view, proxy in
            view.layerEffect(ShaderLibrary.frost(.float2(proxy.size), .float(p), .float(tm), .float2(t)),
                             maxSampleOffset: CGSize(width: 8, height: 8),
                             isEnabled: p > 0.001)
        }
    }
}

// MARK: - Chip

struct ChipView: View {
    var width: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: width * 0.16, style: .continuous)
        shape
            .fill(LinearGradient(colors: [Color(hex: 0xF1E3B8), Color(hex: 0xCDB57C), Color(hex: 0xE9D9A6)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                ChipContacts()
                    .stroke(Color(hex: 0x9C8248).opacity(0.7), lineWidth: max(0.6, width * 0.018))
            }
            .overlay(shape.strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
            .frame(width: width, height: width * 0.78)
    }
}

private struct ChipContacts: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let pad = CGRect(x: r.width * 0.36, y: r.height * 0.28, width: r.width * 0.28, height: r.height * 0.44)
        p.addRoundedRect(in: pad, cornerSize: CGSize(width: r.width * 0.05, height: r.width * 0.05))
        for y in [0.33, 0.67] {
            p.move(to: CGPoint(x: 0, y: r.height * y))
            p.addLine(to: CGPoint(x: pad.minX, y: r.height * y))
            p.move(to: CGPoint(x: pad.maxX, y: r.height * y))
            p.addLine(to: CGPoint(x: r.width, y: r.height * y))
        }
        p.move(to: CGPoint(x: r.midX, y: 0))
        p.addLine(to: CGPoint(x: r.midX, y: pad.minY))
        p.move(to: CGPoint(x: r.midX, y: pad.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.height))
        return p
    }
}
