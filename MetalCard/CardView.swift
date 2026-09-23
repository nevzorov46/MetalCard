import SwiftUI

/// The card itself: gradient body, Metal sheen that follows the tilt,
/// frost that creeps in from the edges when the card is frozen, and a flip to the back.
struct CardView: View {
    let card: Card
    var tilt: CGSize = .zero
    var freeze: Double = 0          // 0...1
    var revealed: Bool = false
    var flipped: Bool = false
    var compact: Bool = false

    private let corner: CGFloat = 26

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                body(at: time)
                    .opacity(flipped ? 0 : 1)

                back(at: time)
                    .opacity(flipped ? 1 : 0)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
            .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
        }
        .aspectRatio(1.586, contentMode: .fit)   // ISO/IEC 7810 ID-1, same as a real card
    }

    // MARK: Front

    private func body(at time: TimeInterval) -> some View {
        ZStack {
            shape
                .fill(
                    LinearGradient(colors: [card.top, card.bottom],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(grain)
                .overlay(sheen(at: time))
                .overlay(frost(at: time))
                .overlay(
                    shape.strokeBorder(.white.opacity(0.14), lineWidth: 0.8)
                )

            front
                .opacity(compact ? 0.9 : 1)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.45), radius: compact ? 14 : 28, x: 0, y: compact ? 8 : 18)
    }

    private var front: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(card.label.uppercased())
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                chip
            }

            Spacer(minLength: 0)

            Text(revealed ? card.groupedNumber : card.maskedNumber)
                .font(.system(size: compact ? 17 : 21, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.95))
                .contentTransition(.numericText())
                .blur(radius: revealed ? 0 : 2.5)
                .animation(.smooth(duration: 0.45), value: revealed)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.holder)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .tracking(1.2)
                    Text("VALID  \(card.expiry)")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Text("VISA")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .italic()
                    .foregroundStyle(.white.opacity(0.9))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.top, 14)
        }
        .padding(compact ? 18 : 24)
    }

    private var chip: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(
                LinearGradient(colors: [Color(white: 0.92), Color(white: 0.62)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .frame(width: 34, height: 26)
            .overlay(
                VStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle().fill(.black.opacity(0.18)).frame(height: 1)
                    }
                }
                .padding(.horizontal, 5)
            )
    }

    // MARK: Back

    private func back(at time: TimeInterval) -> some View {
        ZStack {
            shape
                .fill(LinearGradient(colors: [card.bottom, card.top],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(grain)
                .overlay(sheen(at: time))
                .overlay(frost(at: time))

            VStack(spacing: 16) {
                Rectangle().fill(.black.opacity(0.85)).frame(height: 44)
                HStack {
                    Spacer()
                    Text(revealed ? card.cvv : "•••")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .contentTransition(.numericText())
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(.black.opacity(0.8))
                        .blur(radius: revealed ? 0 : 2)
                        .animation(.smooth(duration: 0.4), value: revealed)
                }
                .padding(.horizontal, 24)
                Spacer()
            }
            .padding(.top, 28)
        }
        .compositingGroup()
    }

    // MARK: Layers

    private var shape: some InsettableShape {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
    }

    private var grain: some View {
        shape
            .fill(.white.opacity(0.03))
            .blendMode(.overlay)
    }

    private func sheen(at time: TimeInterval) -> some View {
        GeometryReader { geo in
            Rectangle()
                .foregroundStyle(.white)
                .colorEffect(
                    ShaderLibrary.sheen(
                        .float2(geo.size),
                        .float2(tilt),
                        .float(time)
                    )
                )
                .blendMode(.plusLighter)
        }
        .clipShape(shape)
        .allowsHitTesting(false)
    }

    private func frost(at time: TimeInterval) -> some View {
        GeometryReader { geo in
            Rectangle()
                .foregroundStyle(.white)
                .colorEffect(
                    ShaderLibrary.frost(
                        .float2(geo.size),
                        .float(freeze),
                        .float(time)
                    )
                )
        }
        .clipShape(shape)
        .opacity(freeze > 0 ? 1 : 0)
        .allowsHitTesting(false)
    }
}
