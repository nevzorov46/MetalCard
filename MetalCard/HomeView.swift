import SwiftUI

/// Home: balance, quick actions, the card carousel and recent activity.
///
/// Opening a card is a hero zoom: one card on a layer above everything flies between two slots,
/// its place in the carousel and its place at the top of `CardDetailView`, while the detail
/// screen fades in underneath. Pull the card down (or tap back) and it flies home again.
struct HomeView: View {
    @Environment(Wallet.self) private var wallet
    @Environment(MotionTilt.self) private var motion
    @Environment(\.theme) private var palette
    @Namespace private var hero

    @State private var currentCard: Card.ID?
    @State private var selected: Card.ID?        // the detail screen is showing this card
    @State private var flying: Card.ID?          // the hero layer is showing this card
    @State private var showsDetails = false
    @State private var showsThemes = false
    @State private var drag: CGSize = .zero
    @State private var flip: Double = 0           // degrees; each fling to the side adds a half turn
    @GestureState private var holding = false     // a finger is on the open card
    #if DEBUG
    @State private var demoHold = false           // the scripted demo "holding" the card
    #endif

    /// The card is picked up — by a finger, or by the scripted demo.
    private var isHeld: Bool {
        #if DEBUG
        holding || demoHold
        #else
        holding
        #endif
    }

    /// 0...1 — how far the hero card has been pulled down towards closing.
    private var pull: CGFloat { min(max(drag.height, 0) / 260, 1) }
    /// Past this point, letting go closes the card. A tick marks the crossing.
    private var willClose: Bool { drag.height > 110 }

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
        .background(palette.canvas)
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
        // The drag adds to the phone's own tilt, through a rubber band, so the card
        // feels heavier the further you push it.
        let tilt = CGSize(width: motion.tilt.width + Self.rubberBand(drag.width, limit: 140) / 100,
                          height: motion.tilt.height + Self.rubberBand(drag.height, limit: 140) / 100)
        let pivot = Self.pivot(for: tilt)
        let frozen = wallet.isFrozen(card)
        return CardView(card: card, tilt: tilt, frost: frozen ? 1 : 0,
                        showsDetails: showsDetails, lift: isHeld ? 1 : 0, flip: flip)
            // The ice grows slowly and melts faster, whatever animation the tap used —
            // this overrides it for the card alone, so the rest of the screen stays snappy.
            .animation(frozen ? .freeze : .thaw, value: frozen)
            // One turn around the axis at right angles to the push — how a real card pivots
            // when you press on a corner — rather than two turns stacked on each other.
            .rotation3DEffect(pivot.angle, axis: pivot.axis, perspective: 0.55)
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
            // Picked up: a touch larger. Pulled down: smaller, on its way back to the wallet.
            .scaleEffect((isHeld ? 1.03 : 1) * (1 - pull * 0.12))
            // It follows the finger a little sideways and upwards, and fully when pulled down.
            .offset(x: Self.rubberBand(drag.width, limit: 36),
                    y: drag.height > 0 ? drag.height * 0.55 : Self.rubberBand(drag.height, limit: 28))
            .animation(.spring(response: 0.32, dampingFraction: 0.7), value: isHeld)
            .gesture(cardDrag, including: selected == nil ? .none : .all)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.55), trigger: holding) { _, now in now }
            .sensoryFeedback(.selection, trigger: willClose)
            // A knock as the card is flung over — but not when closing turns it face up again.
            .sensoryFeedback(trigger: flip) { _, _ in
                selected == nil ? nil : .impact(weight: .medium, intensity: 0.8)
            }
            // If the gesture is cancelled (a call comes in), nothing calls `onEnded`;
            // settle the card here instead of leaving it tilted.
            .onChange(of: holding) { _, now in
                if !now, drag != .zero {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { drag = .zero }
                }
            }
    }

    /// Touch the open card to pick it up, drag to turn it, fling it sideways to turn it over;
    /// pull it down far enough and it goes back into the wallet.
    private var cardDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($holding) { _, holding, _ in holding = true }
            .onChanged { drag = $0.translation }
            .onEnded { value in
                if value.translation.height > 110 || value.predictedEndTranslation.height > 260 {
                    close()
                    return
                }
                release(velocity: value.velocity)
            }
    }

    /// Letting go. A fast, mostly sideways fling turns the card over; anything gentler
    /// springs it back to rest.
    private func release(velocity v: CGSize) {
        if abs(v.width) > 800, abs(v.width) > abs(v.height) * 1.5 {
            turnOver(speed: v.width)
            // The fling's energy went into the turn, so the tilt just eases home.
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { drag = .zero }
            return
        }
        // Hand the finger's speed to the spring, so a flick carries on for a moment
        // and then swings back, instead of simply stopping.
        let d = drag
        let distance = d.width * d.width + d.height * d.height
        let speed = distance > 1 ? -(v.width * d.width + v.height * d.height) / distance : 0
        withAnimation(.interpolatingSpring(stiffness: 170, damping: 15,
                                           initialVelocity: min(max(speed, -6), 6))) {
            drag = .zero
        }
    }

    /// A half turn in the direction of the fling, carrying on the way the drag was tilting it.
    /// The finger's speed becomes the spring's starting speed, so a harder fling turns it faster.
    private func turnOver(speed: CGFloat) {
        // The spring counts speed in half turns per second. At the card's edge, about 170 pt
        // from the axis, half a turn a second is 170π ≈ 530 pt/s.
        let start = min(max(abs(speed) / 530, 1.5), 7)
        withAnimation(.interpolatingSpring(duration: 0.7, bounce: 0.25, initialVelocity: start)) {
            flip += speed > 0 ? 180 : -180
        }
    }

    /// Moves 1:1 near zero and eases towards ±limit, like a scroll view's overscroll.
    private static func rubberBand(_ x: CGFloat, limit: CGFloat) -> CGFloat {
        let sign: CGFloat = x < 0 ? -1 : 1
        return sign * limit * (1 - 1 / (1 + abs(x) / limit))
    }

    /// A single rotation around the axis perpendicular to the tilt.
    private static func pivot(for tilt: CGSize) -> (angle: Angle, axis: (x: CGFloat, y: CGFloat, z: CGFloat)) {
        let magnitude = (tilt.width * tilt.width + tilt.height * tilt.height).squareRoot()
        guard magnitude > 0.0001 else { return (.zero, (x: 0, y: 1, z: 0)) }
        return (.degrees(min(magnitude, 1.4) * 9),
                (x: -tilt.height / magnitude, y: tilt.width / magnitude, z: 0))
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
            // Face up for the wallet: on to the nearest whole turn, so a card showing its back
            // keeps turning the way it last went while it flies home.
            flip = (flip / 360).rounded() * 360
        } completion: {
            flying = nil
            flip = 0
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("VN")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(palette.onAccent)
                .frame(width: 44, height: 44)
                .background(palette.accent, in: Circle())
            Spacer()
            Button { showsThemes = true } label: { roundIcon("paintpalette.fill") }
                .buttonStyle(.plain)
            roundIcon("bell.fill")
        }
        .padding(.horizontal, 24)
        .sheet(isPresented: $showsThemes) {
            ThemePicker()
                .presentationDetents([.height(330)])
                .presentationDragIndicator(.visible)
        }
    }

    private func roundIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(palette.ink)
            .frame(width: 44, height: 44)
            .background(palette.surface, in: Circle())
    }

    // MARK: Balance

    private var balance: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Total balance")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.inkTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("€12,480")
                    .font(.display(58))
                    .foregroundStyle(palette.ink)
                Text(".20")
                    .font(.display(34))
                    .foregroundStyle(palette.inkTertiary)
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
        .foregroundStyle(primary ? palette.onAccent : palette.ink)
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(primary ? palette.accent : palette.surface, in: Capsule())
    }

    private func sectionTitle(_ title: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(palette.ink)
            Spacer()
            Text(trailing)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.inkTertiary)
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
                    .fill(active ? palette.ink : palette.ink.opacity(0.16))
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
                        .foregroundStyle(palette.ink)
                        .frame(width: 48, height: 48)
                        .background(palette.surface, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tx.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(palette.ink)
                        Text(tx.subtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(palette.inkTertiary)
                    }
                    Spacer()
                    Text(tx.amount)
                        .font(.system(size: 16, weight: .semibold).monospacedDigit())
                        .foregroundStyle(tx.incoming ? palette.positive : palette.ink)
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
    /// `-openFrozen` starts on the first card, already frozen; `-openBack` starts on its back;
    /// `-demoFlip` flings the card over left, right and left again, then closes it;
    /// `-startCard <id>` centres that card in the carousel (and the demos use it);
    /// `-frozen` freezes it and `-details` shows its details first;
    /// `-showThemes` opens the theme sheet.
    func playDemoIfRequested() async {
        let arguments = ProcessInfo.processInfo.arguments
        if let i = arguments.firstIndex(of: "-startCard"), i + 1 < arguments.count {
            currentCard = arguments[i + 1]
        }
        if arguments.contains("-showThemes") {
            showsThemes = true
        }
        guard let card = currentCard.flatMap({ wallet.card($0) }) ?? wallet.cards.first else { return }
        if arguments.contains("-frozen") {
            wallet.frozen.insert(card.id)
        }
        if arguments.contains("-details") {
            showsDetails = true
        }

        if arguments.contains("-openFrozen") {
            wallet.frozen.insert(card.id)
            flying = card.id
            selected = card.id
            return
        }

        if arguments.contains("-openBack") {
            flip = 180
            flying = card.id
            selected = card.id
            return
        }

        if arguments.contains("-demoFlip") {
            try? await Task.sleep(for: .seconds(1.2))
            open(card)
            try? await Task.sleep(for: .seconds(1.4))
            for direction in [-1.0, 1.0, -1.0] {
                // A short, quick push to the side, then let go at speed.
                demoHold = true
                for step in 1...6 {
                    drag = CGSize(width: direction * Double(step) * 12, height: 0)
                    try? await Task.sleep(for: .milliseconds(16))
                }
                demoHold = false
                release(velocity: CGSize(width: direction * 1800, height: 0))
                try? await Task.sleep(for: .seconds(1.8))
            }
            close()
            return
        }

        if arguments.contains("-demoTilt") {
            // Pick the card up and trace a slow figure of eight, as a finger would.
            try? await Task.sleep(for: .seconds(1.2))
            open(card)
            try? await Task.sleep(for: .seconds(1.2))
            demoHold = true
            try? await Task.sleep(for: .seconds(0.3))
            let steps = 120
            for i in 0...steps {
                let a = Double(i) / Double(steps) * 2 * .pi
                drag = CGSize(width: sin(a) * 120, height: sin(2 * a) * 60)
                try? await Task.sleep(for: .milliseconds(22))
            }
            demoHold = false
            withAnimation(.interpolatingSpring(stiffness: 170, damping: 15)) { drag = .zero }
            return
        }

        guard arguments.contains("-demo") else { return }
        try? await Task.sleep(for: .seconds(1.5))
        open(card)
        try? await Task.sleep(for: .seconds(1.6))
        withAnimation(.snappy) { wallet.toggleFreeze(card) }
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
