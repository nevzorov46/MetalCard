import SwiftUI

/// What there is to pay for. A few merchants in a few currencies, so a payment is a
/// choice and not a demo button — and so the wallet has to deal with more than euros.
struct Offer: Identifiable, Hashable {
    let id: String
    let merchant: Merchant
    let amount: Money

    static let all: [Offer] = [
        Offer(id: "flight",
              merchant: Merchant(name: "Monsoon Air", category: "Flight · SIN → NRT", symbol: "airplane",
                                 trip: Trip(airline: "Monsoon Air", flight: "MA 638",
                                            from: "SIN", fromCity: "Singapore", to: "NRT", toCity: "Tokyo Narita",
                                            date: "Fri 24 Oct", departs: "23:55", arrives: "08:05 +1",
                                            gate: "C19", seat: "32A")),
              amount: Money(minorUnits: 48_600, currency: .sgd)),
        Offer(id: "coffee", merchant: Merchant(name: "Tamp & Grind", category: "Coffee · Singapore", symbol: "cup.and.saucer.fill"),
              amount: Money(minorUnits: 480, currency: .sgd)),
        Offer(id: "lunch", merchant: Merchant(name: "Hawker Row", category: "Lunch · Singapore", symbol: "fork.knife"),
              amount: Money(minorUnits: 1_250, currency: .sgd)),
        Offer(id: "ride", merchant: Merchant(name: "Metro Taxi", category: "Ride · Berlin", symbol: "car.fill"),
              amount: Money(minorUnits: 1_840, currency: .eur)),
        Offer(id: "stream", merchant: Merchant(name: "Lumen Streaming", category: "Subscription · New York", symbol: "play.rectangle.fill"),
              amount: Money(minorUnits: 999, currency: .usd)),
        Offer(id: "ramen", merchant: Merchant(name: "Ichiraku", category: "Dinner · Tokyo", symbol: "takeoutbag.and.cup.and.straw.fill"),
              amount: Money(minorUnits: 1_200, currency: .jpy))
    ]
}

/// The pay sheet. The card on top, merchants below; tapping a merchant is the payment —
/// Face ID comes straight up over the list, the row shows where the payment is, and the
/// receipt follows. There is no screen in between asking the same question again.
struct PayView: View {
    @Environment(Wallet.self) private var wallet
    @Environment(\.theme) private var palette
    @Environment(MotionTilt.self) private var motion

    let card: Card
    let gateway: any ChargeGateway
    @Binding var isPresented: Bool

    @State private var checkout: Checkout?
    @State private var paying: Offer?
    @State private var receipt: Receipt?
    /// The merchant a gift card could not cover; nothing was sent for it.
    @State private var shortfall: Offer?

    private var frozen: Bool { wallet.isFrozen(card) }
    private var busy: Bool { checkout?.phase.isBusy ?? false }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header.padding(.top, 26).padding(.bottom, 18)
                    ForEach(Offer.all) { offer in
                        Button { pay(offer) } label: { row(offer) }
                            .buttonStyle(.plain)
                            .disabled(busy || frozen)
                            .opacity((busy && paying != offer) || frozen ? 0.45 : 1)
                    }
                }
                .padding(.bottom, 24)
            }
            .background(palette.canvas)
            .navigationDestination(item: $receipt) { receipt in
                ReceiptView(receipt: receipt, cardName: card.name, art: card.art, holder: card.holder) {
                    isPresented = false
                }
                    .background(palette.canvas)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        .sensoryFeedback(.success, trigger: receipt)
        .sensoryFeedback(.error, trigger: failed)
        .sensoryFeedback(.error, trigger: shortfall)
        .onChange(of: checkout?.phase) { _, phase in
            // Approved: into the wallet at once, then the receipt.
            if case .approved(let r) = phase {
                wallet.record(r, card: card)
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    receipt = r
                }
            }
        }
    }

    // MARK: Paying

    private func pay(_ offer: Offer) {
        // Checked on the device: a gift card's balance is ours to know, and asking the
        // gateway to charge more than is on it would only earn a decline.
        guard wallet.canPay(offer.amount, with: card) else {
            shortfall = offer
            return
        }
        shortfall = nil
        // The same merchant after a failure is the same purchase: same checkout, same key.
        if paying != offer || checkout == nil {
            paying = offer
            checkout = Checkout(amount: offer.amount, merchant: offer.merchant,
                                client: PaymentClient(gateway: gateway))
        }
        checkout?.pay(card: card, isFrozen: frozen)
    }

    private var failed: Bool {
        if case .failed = checkout?.phase { true } else { false }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: 14) {
            CardView(card: card, tilt: motion.tilt, frost: frozen ? 1 : 0)
                .frame(width: 214)
                .animation(frozen ? .freeze : .thaw, value: frozen)
            if frozen {
                Button("Card frozen · Unfreeze") { wallet.toggleFreeze(card) }
                    .font(.system(size: 14, weight: .semibold))
                    .tint(palette.ink)
            } else if let left = wallet.giftBalance(of: card) {
                Text([card.from.map { "From \($0)" }, "\(left.formatted) left"].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(palette.ink)
                    .contentTransition(.numericText())
                    .animation(.smooth, value: left)
            } else {
                Text("Tap to pay")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.inkTertiary)
            }
        }
    }

    private func row(_ offer: Offer) -> some View {
        let active = paying == offer
        return HStack(spacing: 14) {
            Image(systemName: offer.merchant.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.ink)
                .frame(width: 46, height: 46)
                .background(palette.accentSoft, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(offer.merchant.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Text(shortfall == offer ? "Only \(wallet.giftBalance(of: card)?.formatted ?? "") left"
                     : active ? status : offer.merchant.category)
                    .font(.system(size: 13))
                    .foregroundStyle((active && failed) || shortfall == offer ? palette.ink : palette.inkTertiary)
                    .contentTransition(.opacity)
                    .animation(.smooth(duration: 0.25), value: status)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(offer.amount.formatted)
                    .font(.system(size: 16, weight: .semibold).monospacedDigit())
                    .foregroundStyle(palette.ink)
                if offer.amount.currency != .home {
                    Text("≈ " + FX.convert(offer.amount, to: .home).formatted)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(palette.inkTertiary)
                }
            }
            Group {
                if active && busy {
                    ProgressView().tint(palette.inkTertiary)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.inkTertiary)
                }
            }
            .frame(width: 18)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(active && busy ? palette.surface : .clear)
        .contentShape(Rectangle())
    }

    /// What the active row says while it is paying.
    private var status: String {
        switch checkout?.phase {
        case .confirming:                     "Confirm with Face ID"
        case .charging(let n) where n > 1:    "No answer — retrying with the same key"
        case .charging:                       "Paying…"
        case .approved:                       "Paid"
        case .failed(let error):              "\(error.message) · tap to try again"
        default:                              ""
        }
    }
}
