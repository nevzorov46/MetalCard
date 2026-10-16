import SwiftUI

/// The receipt for a flight is a boarding pass, drawn in the same hand as the gift cards:
/// the card's illustration across the top, the route over it, a torn line, and the details
/// with a barcode below. The barcode is made from the charge id, so it differs per booking.
struct TicketView: View {
    @Environment(\.theme) private var palette

    let trip: Trip
    let art: CardArt
    let holder: String
    let chargeID: String

    private let topHeight: CGFloat = 176

    var body: some View {
        VStack(spacing: 0) {
            top
            bottom
        }
        .clipShape(TicketShape(notchY: topHeight))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
    }

    // MARK: The illustrated half

    private var top: some View {
        ZStack {
            art.base
            // Lifted a little, so a moon or a sun sits above the codes rather than behind them.
            CardArtView(art: art)
                .offset(y: -16)
            // A band at the top for the header and one at the bottom for the codes, so both
            // read over any of the drawings.
            LinearGradient(stops: [.init(color: art.base.opacity(0.82), location: 0),
                                   .init(color: art.base.opacity(0), location: 0.30),
                                   .init(color: art.base.opacity(0), location: 0.50),
                                   .init(color: art.base.opacity(0.9), location: 1)],
                           startPoint: .top, endPoint: .bottom)

            VStack(spacing: 0) {
                HStack {
                    Text("BOARDING PASS")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(2.2)
                    Spacer()
                    Text("\(trip.airline) · \(trip.flight)")
                        .font(.system(size: 12, weight: .semibold))
                }
                .opacity(0.85)

                Spacer(minLength: 0)

                HStack(alignment: .bottom) {
                    airport(trip.from, trip.fromCity, alignment: .leading)
                    route
                    airport(trip.to, trip.toCity, alignment: .trailing)
                }
            }
            .foregroundStyle(art.ink)
            .padding(18)
        }
        .frame(height: topHeight)
    }

    private func airport(_ code: String, _ city: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(code)
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .monospacedDigit()
            Text(city)
                .font(.system(size: 12, weight: .medium))
                .opacity(0.8)
        }
    }

    private var route: some View {
        HStack(spacing: 6) {
            DashedLine().stroke(style: StrokeStyle(lineWidth: 1.4, dash: [3, 4]))
            Image(systemName: "airplane")
                .font(.system(size: 17, weight: .semibold))
            DashedLine().stroke(style: StrokeStyle(lineWidth: 1.4, dash: [3, 4]))
        }
        .frame(height: 20)
        .padding(.horizontal, 10)
        .padding(.bottom, 26)
        .opacity(0.85)
    }

    // MARK: The paper half

    private var bottom: some View {
        VStack(alignment: .leading, spacing: 16) {
            DashedLine()
                .stroke(palette.inkTertiary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                .frame(height: 1)
                .padding(.horizontal, 6)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow {
                    field("DATE", trip.date)
                    field("DEPARTS", trip.departs)
                    field("ARRIVES", trip.arrives)
                }
                GridRow {
                    field("PASSENGER", passenger)
                    field("GATE", trip.gate)
                    field("SEAT", trip.seat)
                }
            }

            VStack(spacing: 6) {
                Barcode(seed: chargeID)
                    .fill(palette.ink)
                    .frame(height: 46)
                Text(chargeID)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.inkTertiary)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface)
    }

    /// "VALERY NEVZOROV" → "NEVZOROV / VALERY", the way a ticket prints a name.
    private var passenger: String {
        let parts = holder.split(separator: " ")
        guard parts.count >= 2 else { return holder }
        return "\(parts.last!) / \(parts.dropLast().joined(separator: " "))"
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(palette.inkTertiary)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Shapes

/// A rounded ticket with a semicircle bitten out of each side where it would tear.
struct TicketShape: Shape {
    var notchY: CGFloat
    var radius: CGFloat = 18
    var notch: CGFloat = 11

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        let left = Path(ellipseIn: CGRect(x: rect.minX - notch, y: rect.minY + notchY - notch,
                                          width: notch * 2, height: notch * 2))
        let right = Path(ellipseIn: CGRect(x: rect.maxX - notch, y: rect.minY + notchY - notch,
                                           width: notch * 2, height: notch * 2))
        path = path.subtracting(left).subtracting(right)
        return path
    }
}

struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// Bars of one to three units, from the bytes of a string. Not a real symbology — it only
/// has to look like one, and look different for every booking.
struct Barcode: Shape {
    let seed: String

    func path(in rect: CGRect) -> Path {
        let bytes = Array(seed.utf8)
        guard !bytes.isEmpty else { return Path() }
        var widths: [Int] = []
        var i = 0
        while widths.reduce(0, +) < 120 {
            let b = bytes[i % bytes.count] &+ UInt8(truncatingIfNeeded: i * 31)
            widths.append(Int(b % 3) + 1)
            i += 1
        }
        let unit = rect.width / CGFloat(widths.reduce(0, +))
        var path = Path()
        var x = rect.minX
        for (n, w) in widths.enumerated() {
            let width = CGFloat(w) * unit
            if n.isMultiple(of: 2) { path.addRect(CGRect(x: x, y: rect.minY, width: width, height: rect.height)) }
            x += width
        }
        return path
    }
}
