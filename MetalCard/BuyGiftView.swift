import SwiftUI

/// Where gift cards come from: pick a drawing and an amount, pay for it with one of your
/// own cards, and the new card lands in the wallet with that amount on it. The purchase
/// goes through the same checkout as any other — same key, same lost-answer handling.
struct BuyGiftView: View {
    @Environment(Wallet.self) private var wallet
    @Environment(\.theme) private var palette
    @Environment(MotionTilt.self) private var motion

    let funding: Card
    let gateway: any ChargeGateway
    let onDone: (Card?) -> Void

    @State private var art: CardArt = .night
    @State private var amount = 20_000
    @State private var checkout: Checkout?
    @State private var bought: Card?

    private static let amounts = [5_000, 10_000, 20_000, 50_000]

    private var price: Money { Money(minorUnits: amount, currency: .sgd) }
    private var busy: Bool { checkout?.phase.isBusy ?? false }
    private var frozen: Bool { wallet.isFrozen(funding) }

    /// What the card will look like, before it exists.
    private var draft: Card {
        Card(id: "draft", name: "\(art.displayName) gift", number: "000000000000····",
             expiry: "", cvv: "", holder: funding.holder, style: .primary, art: art)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(bought == nil ? "Buy a gift card" : "In your wallet")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(palette.ink)
                    .contentTransition(.opacity)
                Text(bought == nil
                     ? "Paid with \(funding.name) ···· \(funding.last4)"
                     : "\(price.formatted) to spend, wherever cards are taken")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.inkTertiary)
                    .contentTransition(.opacity)
            }
            .padding(.top, 28)

            CardView(card: bought ?? draft, tilt: motion.tilt)
                .frame(width: 270)
                .padding(.top, 22)
                .id(bought?.id ?? "draft-\(art.rawValue)")
                .transition(.scale(scale: 0.92).combined(with: .opacity))

            if bought == nil {
                picker.padding(.top, 24)
                amounts.padding(.top, 18)
            }

            Spacer(minLength: 16)

            Text(status)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.inkTertiary)
                .frame(height: 18)
                .padding(.bottom, 10)

            button
                .padding(.horizontal, 24)
                .padding(.bottom, 26)
        }
        .background(palette.canvas)
        .animation(.smooth(duration: 0.35), value: art)
        .animation(.smooth(duration: 0.45), value: bought)
        .sensoryFeedback(.success, trigger: bought)
        .onChange(of: checkout?.phase) { _, phase in
            guard case .approved(let receipt) = phase, bought == nil else { return }
            // The purchase is a payment from the funding card; the gift card is what it bought.
            wallet.record(receipt, card: funding)
            bought = wallet.addGift(art, amount: price)
        }
    }

    // MARK: Pieces

    private var picker: some View {
        HStack(spacing: 14) {
            ForEach(CardArt.allCases, id: \.self) { option in
                Button { art = option } label: {
                    ZStack {
                        option.base
                        CardArtView(art: option)
                    }
                    .frame(width: 84, height: 53)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(3)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(art == option ? palette.ink : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.displayName)
                .disabled(busy)
            }
        }
    }

    private var amounts: some View {
        HStack(spacing: 10) {
            ForEach(Self.amounts, id: \.self) { value in
                let selected = value == amount
                Button { amount = value } label: {
                    // Whole amounts, so four fit on a line: "SGD 50", not "SGD 50.00".
                    Text("SGD \(value / 100)")
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(selected ? palette.canvas : palette.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(selected ? palette.ink : palette.surface, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
        }
    }

    private var button: some View {
        Button {
            if bought != nil { onDone(bought); return }
            if checkout == nil || checkout?.amount != price {
                checkout = Checkout(amount: price,
                                    merchant: Merchant(name: "Gift card", category: "\(art.displayName) · gift",
                                                       symbol: "gift.fill"),
                                    client: PaymentClient(gateway: gateway))
            }
            checkout?.pay(card: funding, isFrozen: frozen)
        } label: {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(palette.onAccent) }
                Text(title).font(.system(size: 17, weight: .bold))
            }
            .foregroundStyle(palette.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(palette.accent, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private var title: String {
        if bought != nil { return "Done" }
        switch checkout?.phase {
        case .confirming: return "Confirm with Face ID"
        case .charging:   return "Paying"
        case .failed:     return "Try again"
        default:          return "Buy · \(price.formatted)"
        }
    }

    private var status: String {
        switch checkout?.phase {
        case .charging(let n) where n > 1: "No answer — retrying with the same key"
        case .failed(let error):           error.message
        default:                           ""
        }
    }
}
