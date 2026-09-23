import SwiftUI

/// Wallet stack → tap → the card flies out into detail (matchedGeometryEffect),
/// with reveal, flip and freeze controls. This is the screen you record for the post.
struct WalletView: View {
    @StateObject private var motion = MotionTilt()
    @Namespace private var cardSpace

    @State private var cards = Card.samples
    @State private var selected: Card?
    @State private var revealed = false
    @State private var flipped = false
    @State private var freeze: Double = 0
    @State private var dragTilt: CGSize = .zero

    private var tilt: CGSize {
        CGSize(width: motion.value.width + dragTilt.width,
               height: motion.value.height + dragTilt.height)
    }

    var body: some View {
        ZStack {
            background

            if let card = selected {
                detail(card)
            } else {
                stack
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.82), value: selected)
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
    }

    // MARK: Stack

    private var stack: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Wallet")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

            ZStack {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    CardView(card: card, tilt: tilt, compact: true)
                        .matchedGeometryEffect(id: card.id, in: cardSpace)
                        .padding(.horizontal, 24)
                        .offset(y: CGFloat(index) * 92)
                        .zIndex(Double(index))
                        .onTapGesture {
                            revealed = false; flipped = false; freeze = 0
                            selected = card
                        }
                }
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(.top, 60)
    }

    // MARK: Detail

    private func detail(_ card: Card) -> some View {
        VStack(spacing: 32) {
            HStack {
                Button {
                    selected = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(12)
                        .background(.white.opacity(0.08), in: Circle())
                }
                Spacer()
            }
            .padding(.horizontal, 20)

            CardView(card: card, tilt: tilt, freeze: freeze, revealed: revealed, flipped: flipped)
                .matchedGeometryEffect(id: card.id, in: cardSpace)
                .padding(.horizontal, 20)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragTilt = CGSize(width: value.translation.width / 160,
                                              height: value.translation.height / 160)
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                                dragTilt = .zero
                            }
                        }
                )

            controls

            Spacer()
        }
        .padding(.top, 60)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            control(revealed ? "eye.slash" : "eye", "Details", active: revealed) {
                withAnimation(.smooth(duration: 0.4)) { revealed.toggle() }
            }
            control("arrow.trianglehead.2.clockwise.rotate.90", "Flip", active: flipped) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { flipped.toggle() }
            }
            control("snowflake", "Freeze", active: freeze > 0.5) {
                withAnimation(.easeInOut(duration: freeze > 0.5 ? 0.7 : 1.5)) {
                    freeze = freeze > 0.5 ? 0 : 1
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func control(_ icon: String, _ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .symbolEffect(.bounce, value: active)
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(active ? .white.opacity(0.16) : .white.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(.white.opacity(active ? 1 : 0.8))
        }
        .buttonStyle(.plain)
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            Color(red: 0.03, green: 0.035, blue: 0.05)
            RadialGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.32).opacity(0.75), .clear],
                           center: .init(x: 0.5 + tilt.width * 0.08, y: 0.25 + tilt.height * 0.06),
                           startRadius: 10, endRadius: 520)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    WalletView()
}
