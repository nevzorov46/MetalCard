import SwiftUI

/// Home: balance, quick actions, the card carousel and recent activity.
///
/// Opening a card is a hero zoom: one card on a layer above everything flies between two slots,
/// its place in the carousel and its place at the top of `CardDetailView`, while the detail
/// screen fades in underneath. Pull the card down (or tap back) and it flies home again.
struct HomeView: View {
    @Environment(Wallet.self) private var wallet
    @Environment(MotionTilt.self) private var motion
    @Namespace private var hero

    @State private var currentCard: Card.ID?
    @State private var selected: Card.ID?        // the detail screen is showing this card
    @State private var flying: Card.ID?          // the hero layer is showing this card
    @State private var showsDetails = false
    @State private var drag: CGSize = .zero

    /// 0...1 — how far the hero card has been pulled down towards closing.
    private var pull: CGFloat { min(max(drag.height, 0) / 260, 1) }

    static func slot(_ id: Card.ID) -> String { "slot-\(id)" }

    var body: some View {
        ZStack(alignment: .top) {
            home
                .allowsHitTesting(selected == nil)

            if let id = selected, let card = wallet.card(id) {
                CardDetailView(card: card, hero: hero, showsDetails: $showsDetails, pull: pull, onClose: close)
                    .transition(.opacity.animation(.easeOut(duration: 0.22)))
                    .zIndex(1)
            }

            if let id = flying, let card = wallet.card(id) {
                heroCard(card)
                    .transition(.identity)
                    .zIndex(2)
            }
        }
        .background(Palette.canvas)
        .sensoryFeedback(.impact(weight: .light), trigger: selected)
        .onAppear { currentCard = currentCard ?? wallet.cards.first?.id }
        #if DEBUG
        .task { await playDemoIfRequested() }
        #endif
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.bottom, 28)
                balance.padding(.bottom, 20)
                actions.padding(.bottom, 38)
                sectionTitle("Cards", trailing: "\(wallet.cards.count) cards").padding(.bottom, 16)
                carousel.padding(.bottom, 18)
                pageDots.padding(.bottom, 40)
                sectionTitle("Transactions", trailing: "See all").padding(.bottom, 18)
                transactions
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Hero

    private func heroCard(_ card: Card) -> some View {
        let tilt = CGSize(width: motion.tilt.width + drag.width / 160,
                          height: motion.tilt.height + drag.height / 160)
        return CardView(card: card, tilt: tilt, frost: wallet.isFrozen(card) ? 1 : 0, showsDetails: showsDetails)
            .rotation3DEffect(.degrees(tilt.width * 6), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .rotation3DEffect(.degrees(-tilt.height * 4), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            // Follows whichever slot is the source: the carousel or the detail screen.
            .matchedGeometryEffect(id: Self.slot(card.id), in: hero, isSource: false)
            // Mid-flight the card lifts towards you — grows and leans back — then settles.
            // That lift is what makes the move read as a zoom rather than a slide.
            .keyframeAnimator(initialValue: Lift(), trigger: selected) { content, lift in
                content
                    .scaleEffect(lift.scale)
                    .rotation3DEffect(.degrees(lift.lean), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1.07, duration: 0.22)
                    SpringKeyframe(1.0, duration: 0.45, spring: .bouncy(duration: 0.45, extraBounce: 0.05))
                }
                KeyframeTrack(\.lean) {
                    CubicKeyframe(9, duration: 0.2)
                    SpringKeyframe(0, duration: 0.5, spring: .smooth(duration: 0.5))
                }
            }
            .scaleEffect(1 - pull * 0.1)
            .offset(y: max(drag.height, 0) * 0.5)
            .gesture(cardDrag, including: selected == nil ? .none : .all)
    }

    /// Drag the open card to tilt it; pull it down far enough and it goes back into the wallet.
    private var cardDrag: some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                if value.translation.height > 110 || value.predictedEndTranslation.height > 260 {
                    close()
                } else {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) { drag = .zero }
                }
            }
    }

    private func open(_ card: Card) {
        // Put the hero card over the carousel card first; on the next turn of the run loop,
        // switch the source to the detail slot so the card has somewhere to fly from.
        flying = card.id
        Task { @MainActor in
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { selected = card.id }
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
            selected = nil
            showsDetails = false
            drag = .zero
        } completion: {
            flying = nil
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("VN")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Palette.forest)
                .frame(width: 44, height: 44)
                .background(Palette.lime, in: Circle())
            Spacer()
            roundIcon("magnifyingglass")
            roundIcon("bell.fill")
        }
        .padding(.horizontal, 24)
    }

    private func roundIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .frame(width: 44, height: 44)
            .background(Palette.surface, in: Circle())
    }

    // MARK: Balance

    private var balance: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Total balance")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.inkTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("€12,480")
                    .font(.display(58))
                    .foregroundStyle(Palette.ink)
                Text(".20")
                    .font(.display(34))
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
        .padding(.horizontal, 24)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            pill("Send", "arrow.up.right", primary: true)
            pill("Add money", "plus")
            pill("Request", "arrow.down.left")
        }
        .padding(.horizontal, 24)
    }

    private func pill(_ title: String, _ symbol: String, primary: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold))
            Text(title).font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(primary ? Palette.forest : Palette.ink)
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(primary ? Palette.lime : Palette.surface, in: Capsule())
    }

    private func sectionTitle(_ title: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Palette.ink)
            Spacer()
            Text(trailing)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.inkTertiary)
        }
        .padding(.horizontal, 24)
    }

    // MARK: Cards

    private var carousel: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(wallet.cards) { card in
                    ZStack {
                        Color.clear
                        // Hidden while its hero twin is in flight or open, so there is only one card.
                        CardView(card: card, tilt: motion.tilt, frost: wallet.isFrozen(card) ? 1 : 0)
                            .opacity(flying == card.id ? 0 : 1)
                    }
                    .aspectRatio(CardView.aspect, contentMode: .fit)
                    // The slot is the hero's source only while the card is closed. When it's open,
                    // the id moves to a group of its own, so the detail slot becomes the source.
                    .matchedGeometryEffect(id: selected == card.id ? "idle-\(card.id)" : Self.slot(card.id),
                                           in: hero)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if card.id == currentCard {
                            open(card)
                        } else {
                            withAnimation(.snappy) { currentCard = card.id }
                        }
                    }
                    // `length` already excludes the carousel's content margins.
                    .containerRelativeFrame(.horizontal)
                    .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                        // Shrink and turn each neighbour around the edge that faces the
                        // centre card, so it stays peeking in instead of sliding off-screen.
                        let anchor: UnitPoint = phase.value > 0 ? .leading : .trailing
                        return content
                            .scaleEffect(phase.isIdentity ? 1 : 0.9, anchor: anchor)
                            .rotation3DEffect(.degrees(phase.value * -12), axis: (x: 0, y: 1, z: 0),
                                              anchor: anchor, perspective: 0.5)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $currentCard)
        // Wider than the page margin, so the neighbours peek in on both sides.
        .contentMargins(.horizontal, 34, for: .scrollContent)
        .scrollClipDisabled()
        .scrollIndicators(.hidden)
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(wallet.cards) { card in
                let active = card.id == currentCard
                Capsule()
                    .fill(active ? Palette.ink : Palette.ink.opacity(0.16))
                    .frame(width: active ? 20 : 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy(duration: 0.3), value: currentCard)
    }

    // MARK: Transactions

    private var transactions: some View {
        VStack(spacing: 18) {
            ForEach(wallet.transactions) { tx in
                HStack(spacing: 14) {
                    Image(systemName: tx.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 48, height: 48)
                        .background(Palette.surface, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tx.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                        Text(tx.subtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.inkTertiary)
                    }
                    Spacer()
                    Text(tx.amount)
                        .font(.system(size: 16, weight: .semibold).monospacedDigit())
                        .foregroundStyle(tx.incoming ? Palette.positive : Palette.ink)
                }
            }
        }
        .padding(.horizontal, 24)
    }
}

#if DEBUG
extension HomeView {
    /// Launch arguments for recording and for checking looks without touching the screen:
    /// `-demo` plays a scripted walkthrough (zoom in, freeze, zoom back out);
    /// `-openFrozen` starts on the first card, already frozen.
    func playDemoIfRequested() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard let card = wallet.cards.first else { return }

        if arguments.contains("-openFrozen") {
            wallet.frozen.insert(card.id)
            flying = card.id
            selected = card.id
            return
        }

        guard arguments.contains("-demo") else { return }
        try? await Task.sleep(for: .seconds(1.5))
        open(card)
        try? await Task.sleep(for: .seconds(1.6))
        withAnimation(.freeze) { wallet.toggleFreeze(card) }
        try? await Task.sleep(for: .seconds(4.2))
        close()
    }
}
#endif

/// Keyframed values for the hero card's lift during the zoom.
private struct Lift {
    var scale: CGFloat = 1
    var lean: Double = 0
}
