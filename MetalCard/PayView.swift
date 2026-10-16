import SwiftUI

/// What a terminal asks for. Merchants in several currencies, so the wallet has to deal
/// with more than euros. Each tap at a reader brings the next one.
struct Offer: Identifiable, Hashable {
    let id: String
    let merchant: Merchant
    let amount: Money

    static let all: [Offer] = [
        Offer(id: "coffee", merchant: Merchant(name: "Tamp & Grind", category: "Coffee · Singapore", symbol: "cup.and.saucer.fill"),
              amount: Money(minorUnits: 480, currency: .sgd)),
        Offer(id: "lunch", merchant: Merchant(name: "Hawker Row", category: "Lunch · Singapore", symbol: "fork.knife"),
              amount: Money(minorUnits: 1_250, currency: .sgd)),
        Offer(id: "ride", merchant: Merchant(name: "Metro Taxi", category: "Ride · Berlin", symbol: "car.fill"),
              amount: Money(minorUnits: 1_840, currency: .eur)),
        Offer(id: "ramen", merchant: Merchant(name: "Ichiraku", category: "Dinner · Tokyo", symbol: "takeoutbag.and.cup.and.straw.fill"),
              amount: Money(minorUnits: 1_200, currency: .jpy)),
        Offer(id: "flight",
              merchant: Merchant(name: "Monsoon Air", category: "Changi airport desk · SIN → NRT", symbol: "airplane",
                                 trip: Trip(airline: "Monsoon Air", flight: "MA 638",
                                            from: "SIN", fromCity: "Singapore", to: "NRT", toCity: "Tokyo Narita",
                                            date: "Fri 24 Oct", departs: "23:55", arrives: "08:05 +1",
                                            gate: "C19", seat: "32A")),
              amount: Money(minorUnits: 48_600, currency: .sgd))
    ]
}

/// Paying at a till. The card comes up full size and the phone waits to be held near the
/// reader; the terminal sends who is asking and how much, Face ID confirms it, and the
/// receipt follows. Nothing here is a list to choose from — in a shop, the shop decides
/// what you are paying for.
struct PayView: View {
    @Environment(Wallet.self) private var wallet
    @Environment(\.theme) private var palette
    @Environment(MotionTilt.self) private var motion

    let card: Card
    let gateway: any ChargeGateway
    @Binding var isPresented: Bool

    /// Which terminal comes next, so each visit to a reader is a different shop.
    @AppStorage("terminal.next") private var next = 0

    @State private var offer: Offer?
    @State private var checkout: Checkout?
    @State private var receipt: Receipt?
    @State private var shortfall = false

    private var frozen: Bool { wallet.isFrozen(card) }
    private var busy: Bool { checkout?.phase.isBusy ?? false }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Cancel") { checkout?.cancel(); isPresented = false }
                        .font(.system(size: 16, weight: .semibold))
                        .tint(palette.inkSecondary)
                        .disabled(busy)
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)

                CardView(card: card, tilt: motion.tilt, frost: frozen ? 1 : 0)
                    .frame(width: 300)
                    .padding(.top, 14)
                    .animation(frozen ? .freeze : .thaw, value: frozen)

                Spacer(minLength: 16)

                if let offer {
                    request(offer)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    reader
                        .transition(.opacity)
                }

                Spacer(minLength: 16)

                footer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 26)
            }
            .frame(maxWidth: .infinity)
            .background(palette.canvas)
            .navigationDestination(item: $receipt) { receipt in
                ReceiptView(receipt: receipt, cardName: card.name, art: card.art, holder: card.holder) {
                    isPresented = false
                }
                .background(palette.canvas)
                .toolbar(.hidden, for: .navigationBar)
            }
        }
        .animation(.smooth(duration: 0.45), value: offer)
        .animation(.smooth(duration: 0.3), value: checkout?.phase)
        .sensoryFeedback(.impact(weight: .medium), trigger: offer)
        .sensoryFeedback(.success, trigger: receipt)
        .sensoryFeedback(.error, trigger: failed)
        .sensoryFeedback(.error, trigger: shortfall)
        .task(id: frozen) { await waitForTerminal() }
        .onChange(of: checkout?.phase) { _, phase in
            if case .approved(let r) = phase {
                wallet.record(r, card: card)
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    receipt = r
                }
            }
        }
    }

    // MARK: The flow

    /// The terminal answers a moment after the phone is held near it. A frozen card is
    /// never presented to a reader at all.
    private func waitForTerminal() async {
        guard !frozen, offer == nil else { return }
        try? await Task.sleep(for: .milliseconds(1_700))
        guard !Task.isCancelled, !frozen, offer == nil else { return }
        let incoming = Offer.all[next % Offer.all.count]
        next += 1
        offer = incoming

        // A gift card can only spend what is on it: said here, before Face ID is asked for.
        guard wallet.canPay(incoming.amount, with: card) else {
            shortfall = true
            return
        }
        checkout = Checkout(amount: incoming.amount, merchant: incoming.merchant,
                            client: PaymentClient(gateway: gateway))
        try? await Task.sleep(for: .milliseconds(650))
        guard !Task.isCancelled else { return }
        checkout?.pay(card: card, isFrozen: frozen)
    }

    private var failed: Bool {
        if case .failed = checkout?.phase { true } else { false }
    }

    // MARK: Pieces

    /// Waiting: rings spreading from the top of the phone, the way a reader is found.
    private var reader: some View {
        VStack(spacing: 18) {
            // Driven by the clock rather than a repeating animation: a repeating animation
            // also catches the sheet sliding in, and the rings fly in from wherever they
            // were drawn first.
            TimelineView(.animation(paused: frozen)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(0..<3) { i in
                        let phase = ((t / 1.8) + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                        Circle()
                            .stroke(palette.ink.opacity(0.35), lineWidth: 1.5)
                            .frame(width: 44, height: 44)
                            .scaleEffect(0.8 + 1.8 * phase)
                            .opacity(frozen ? 0 : 0.9 * (1 - phase))
                    }
                    Image(systemName: frozen ? "snowflake" : "wave.3.right")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(palette.ink)
                }
            }
            .frame(height: 120)

            Text(frozen ? "This card is frozen" : "Hold near the reader")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(palette.ink)
            if let left = wallet.giftBalance(of: card), !frozen {
                Text([card.from.map { "From \($0)" }, "\(left.formatted) left"].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .foregroundStyle(palette.inkTertiary)
            }
        }
    }

    /// What the terminal sent.
    private func request(_ offer: Offer) -> some View {
        VStack(spacing: 10) {
            Image(systemName: offer.merchant.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(palette.ink)
                .frame(width: 52, height: 52)
                .background(palette.surface, in: Circle())
            Text(offer.merchant.name)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(palette.ink)
            Text(offer.merchant.category)
                .font(.system(size: 14))
                .foregroundStyle(palette.inkTertiary)
            Text(offer.amount.formatted)
                .font(.display(44))
                .foregroundStyle(palette.ink)
                .padding(.top, 4)
            if offer.amount.currency != .home {
                Text("≈ " + FX.convert(offer.amount, to: .home).formatted)
                    .font(.system(size: 14).monospacedDigit())
                    .foregroundStyle(palette.inkTertiary)
            }
        }
    }

    @ViewBuilder private var footer: some View {
        VStack(spacing: 12) {
            Text(status)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(shortfall || failed ? palette.ink : palette.inkTertiary)
                .multilineTextAlignment(.center)
                .frame(minHeight: 20)
                .contentTransition(.opacity)

            if frozen {
                wide("Unfreeze card") { wallet.toggleFreeze(card) }
            } else if failed {
                wide("Try again") { checkout?.pay(card: card, isFrozen: frozen) }
            } else if shortfall {
                wide("Done") { isPresented = false }
            } else {
                // While the terminal and Face ID do their part there is nothing to press;
                // the bar only says where things are.
                HStack(spacing: 10) {
                    if offer != nil { ProgressView().tint(palette.inkTertiary) }
                    Text(offer == nil ? "Looking for a terminal" : progress)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func wide(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(palette.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(palette.accent, in: RoundedRectangle(cornerRadius: 16))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var progress: String {
        switch checkout?.phase {
        case .confirming:                  "Confirm with Face ID"
        case .charging(let n) where n > 1: "Retrying"
        case .charging:                    "Paying"
        case .approved:                    "Paid"
        default:                           "Connecting"
        }
    }

    private var status: String {
        if shortfall, let left = wallet.giftBalance(of: card) {
            return "Only \(left.formatted) left on this gift card"
        }
        switch checkout?.phase {
        case .charging(let n) where n > 1: return "No answer — retrying with the same key"
        case .failed(let error):           return error.message
        default:                           return ""
        }
    }
}
