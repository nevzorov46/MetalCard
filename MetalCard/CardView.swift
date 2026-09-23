import SwiftUI

/// The card, front and back. Every size is a fraction of the card's width, so the same view
/// looks identical in the carousel, in the detail screen and in the middle of the zoom.
///
/// Animatable over `flip`: SwiftUI hands it every in-between angle of a turn, so it can swap
/// the faces at the one moment neither can be seen — when the card is edge-on.
struct CardView: View, Animatable {
    static let aspect: CGFloat = 1.586       // ISO/IEC 7810 ID-1, same as a real card
    static let cornerRatio: CGFloat = 0.055

    let card: Card
    var tilt: CGSize = .zero
    var frost: Double = 0                   // 0...1, animatable
    var showsDetails = false
    var lift: CGFloat = 0                   // 0...1, how far the card is picked up
    var flip: Double = 0                    // degrees; the back is up from 90° to 270°

    nonisolated var animatableData: Double {
        get { flip }
        set { flip = newValue }
    }

    @Environment(\.theme) private var palette
    private var base: Color { palette.colourway(card.style).base }
    private var ink: Color { palette.colourway(card.style).ink }

    var body: some View {
        let side = Self.side(flip)
        // Turning the card sweeps the light across it, just as tilting does.
        let light = CGSize(width: tilt.width + sin(side.angle * .pi / 180) * 1.6, height: tilt.height)
        TimelineView(.animation(paused: frost == 0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000)
            GeometryReader { geo in
                let w = geo.size.width
                face(width: w, back: side.isBack, light: light)
                    .modifier(FrostEffect(progress: frost, tilt: light, time: time))
                    .overlay(alignment: .topTrailing) { frozenBadge(width: w) }
                    .rotation3DEffect(.degrees(side.angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
            }
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
        // A soft glow in the card's own colour, plus a short dark contact shadow. Deriving the
        // glow from the base (not the ink) keeps it dark under cards with light lettering.
        // The light is overhead, so the shadow slides away from the tilt, and a card that is
        // picked up casts a longer, softer one.
        .shadow(color: base.opacity(0.40 - lift * 0.08),
                radius: 20 + lift * 14,
                x: -tilt.width * 10,
                y: 14 + lift * 12 - tilt.height * 6)
        .shadow(color: .black.opacity(0.10 - lift * 0.04),
                radius: 3 + lift * 4,
                x: -tilt.width * 2,
                y: 2 + lift * 4)
    }

    /// Which face is up, and how far that face is turned away from the viewer (−90°...90°).
    private static func side(_ flip: Double) -> (isBack: Bool, angle: Double) {
        let a = flip - 360 * (flip / 360).rounded()     // −180...180
        if a > 90 { return (true, a - 180) }
        if a < -90 { return (true, a + 180) }
        return (false, a)
    }

    // MARK: Face

    // Built as overlays on the base fill: overlays never change the size of what they sit on,
    // so the oversized decorative leaf can't push the layout around. Both sides share the
    // plastic — fill, grain, sheen, rim — and differ only in what is printed on it.
    private func face(width w: CGFloat, back: Bool, light: CGSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: w * Self.cornerRatio, style: .continuous)
        let glare = Float(lift)
        let strength: Float = card.finish == .metal ? 0.55 : 0.14
        // Parallax: the print sits "above" the plastic and the leaf "below" it, so they drift
        // apart as the card turns.
        let print = CGSize(width: tilt.width * w * 0.010, height: tilt.height * w * 0.010)
        let under = CGSize(width: -tilt.width * w * 0.022, height: -tilt.height * w * 0.022)
        // The rim catches the light on the side the card is turned towards.
        let rimFrom = UnitPoint(x: 0.5 - light.width * 0.5, y: -light.height * 0.5)
        let rimTo = UnitPoint(x: 0.5 + light.width * 0.5, y: 1 + light.height * 0.5)
        let leaf = LeafShape(vein: false)
            .fill(ink.opacity(0.08))
            .frame(width: w * 1.05, height: w * 1.05)

        return shape
            .fill(base)
            // Gentle light falloff, so the plastic reads as a physical object.
            .overlay(
                shape.fill(LinearGradient(colors: [.white.opacity(0.10), .clear, .black.opacity(0.08)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            // An oversized leaf, tone on tone, sweeping off the right edge of the front.
            // The back shows the same leaf from behind: mirrored, off the left edge.
            .overlay(alignment: .topLeading) {
                if back {
                    leaf.scaleEffect(x: -1)
                        .offset(x: -w * 0.47 + under.width, y: -w * 0.10 + under.height)
                        .transition(.identity)
                } else {
                    leaf.offset(x: w * 0.42 + under.width, y: -w * 0.10 + under.height)
                        .transition(.identity)
                }
            }
            .overlay(
                Rectangle()
                    .fill(.white)
                    .colorEffect(ShaderLibrary.grain(.float(card.finish == .metal ? 0.24 : 0.10),
                                                     .float(card.finish == .metal ? 1 : 0)))
                    .blendMode(.overlay)
            )
            // Swapped outright, never cross-faded: the card is edge-on when it happens.
            .overlay {
                if back {
                    backPrint(width: w, light: light).offset(print).transition(.identity)
                } else {
                    frontPrint(width: w).offset(print).transition(.identity)
                }
            }
            .overlay(
                Rectangle()
                    .fill(.white)
                    .visualEffect { view, proxy in
                        view.colorEffect(ShaderLibrary.sheen(.float2(proxy.size), .float2(light),
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

    private func frontPrint(width w: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                BrandMark(size: w * 0.068, color: ink)
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
                    .overlay(Capsule().strokeBorder(ink.opacity(0.5), lineWidth: 1))
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
        .foregroundStyle(ink)
        .padding(w * 0.064)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Back

    @ViewBuilder
    private func backPrint(width w: CGFloat, light: CGSize) -> some View {
        if card.isVirtual {
            virtualBack(width: w)
        } else {
            plasticBack(width: w, light: light)
        }
    }

    /// Stripe, signature strip and CVV, the small print, and a foil leaf.
    private func plasticBack(width w: CGFloat, light: CGSize) -> some View {
        let h = w / Self.aspect
        let pad = w * 0.064
        return VStack(alignment: .leading, spacing: 0) {
            // The magnetic stripe, where ISO 7811 puts it. Wider than the card, so the
            // parallax never shows its ends.
            Rectangle()
                .fill(LinearGradient(colors: [Color(hex: 0x2C2B31), Color(hex: 0x0D0D10), Color(hex: 0x1C1B20)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: h * 0.19)
                .padding(.horizontal, -w * 0.05)
                .padding(.top, h * 0.10)

            HStack(alignment: .bottom, spacing: w * 0.03) {
                labelled("AUTHORISED SIGNATURE", width: w) { signatureStrip(width: w) }
                labelled("CVV", width: w) { cvvBox(width: w) }
            }
            .padding(.top, h * 0.07)
            .padding(.horizontal, pad)

            Text("This card remains the property of \(Brand.name) and must be returned on request. Use is subject to the cardholder agreement.")
                .font(.system(size: w * 0.017))
                .opacity(0.55)
                .frame(width: w * 0.56, alignment: .leading)
                .padding(.top, h * 0.035)
                .padding(.horizontal, pad)

            Spacer(minLength: 0)

            HStack(alignment: .bottom) {
                backDetails(width: w, cvv: false)
                Spacer(minLength: 0)
                hologram(light: light)
                    .frame(width: w * 0.12, height: w * 0.12)
            }
            .padding([.horizontal, .bottom], pad)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// A virtual card never exists as plastic, so its back carries only the details.
    private func virtualBack(width w: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                BrandMark(size: w * 0.068, color: ink)
                Spacer()
                Text("Virtual card")
                    .font(.system(size: w * 0.034, weight: .semibold))
                    .opacity(0.75)
            }
            Spacer(minLength: 0)
            backDetails(width: w, cvv: true)
        }
        .foregroundStyle(ink)
        .padding(w * 0.064)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The number, name and expiry — dots until "Show details" reveals them.
    private func backDetails(width w: CGFloat, cvv: Bool) -> some View {
        VStack(alignment: .leading, spacing: w * 0.014) {
            Text(showsDetails ? card.groupedNumber : "•••• •••• •••• \(card.last4)")
                .font(.system(size: w * 0.05, weight: .semibold).monospacedDigit())
            HStack(spacing: w * 0.04) {
                Text(card.holder)
                Text("VALID \(showsDetails ? card.expiry : "••/••")")
                if cvv {
                    Text("CVV \(showsDetails ? card.cvv : "•••")")
                }
            }
            .font(.system(size: w * 0.03, weight: .semibold).monospacedDigit())
            .opacity(0.8)
        }
        .contentTransition(.numericText())
        .animation(.smooth(duration: 0.5), value: showsDetails)
    }

    private func labelled(_ label: String, width w: CGFloat,
                          @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: w * 0.008) {
            Text(label)
                .font(.system(size: w * 0.018, weight: .bold))
                .tracking(w * 0.002)
                .opacity(0.6)
            content()
        }
    }

    private func signatureStrip(width w: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Color(hex: 0xF4F1EA))
            Hatch(spacing: w * 0.012)
                .stroke(Color(hex: 0xD9D1BF), lineWidth: 0.5)
            Text(card.holder.capitalized)
                .font(.custom("SnellRoundhand-Bold", fixedSize: w * 0.05))
                .foregroundStyle(Color(hex: 0x23306E))
                .rotationEffect(.degrees(-3))
                .padding(.leading, w * 0.03)
        }
        .frame(width: w * 0.56, height: w / Self.aspect * 0.14)
        .clipShape(RoundedRectangle(cornerRadius: w * 0.006))
    }

    private func cvvBox(width w: CGFloat) -> some View {
        Text(showsDetails ? card.cvv : "•••")
            .font(.system(size: w * 0.04, weight: .semibold).monospacedDigit())
            .italic()
            .foregroundStyle(Color(hex: 0x121116))
            .contentTransition(.numericText())
            .animation(.smooth(duration: 0.5), value: showsDetails)
            .frame(width: w * 0.15, height: w / Self.aspect * 0.14)
            .background(.white, in: RoundedRectangle(cornerRadius: w * 0.006))
    }

    /// A foil leaf. Its rainbow slides with the light as the card turns.
    private func hologram(light: CGSize) -> some View {
        Rectangle()
            .fill(.white)
            .visualEffect { view, proxy in
                view.colorEffect(ShaderLibrary.holo(.float2(proxy.size), .float2(light)))
            }
            .mask { LeafShape(vein: false) }
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
                // Always on a white pill, so always the dark ice ink — the theme's own
                // ice ink is light in the dark theme and would vanish here.
                .foregroundStyle(Color(hex: 0x0B4A73))
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

/// The fine diagonal print on a signature strip, which shows up any scraping.
private struct Hatch: Shape {
    var spacing: CGFloat

    func path(in r: CGRect) -> Path {
        var p = Path()
        // The first layout can be zero-sized; never step by nothing.
        let step = max(spacing, 2)
        var x = r.minX - r.height
        while x < r.maxX {
            p.move(to: CGPoint(x: x, y: r.maxY))
            p.addLine(to: CGPoint(x: x + r.height, y: r.minY))
            x += step
        }
        return p
    }
}
