import SwiftUI

/// What there is to pay for. A few merchants in a few currencies, so a payment is a
/// choice and not a demo button — and so the wallet has to deal with more than euros.
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
        Offer(id: "stream", merchant: Merchant(name: "Lumen Streaming", category: "Subscription · New York", symbol: "play.rectangle.fill"),
              amount: Money(minorUnits: 999, currency: .usd)),
        Offer(id: "ramen", merchant: Merchant(name: "Ichiraku", category: "Dinner · Tokyo", symbol: "takeoutbag.and.cup.and.straw.fill"),
              amount: Money(minorUnits: 1_200, currency: .jpy))
    ]
}

/// The pay sheet: pick a merchant, then the checkout for it. Both stay inside this one
/// sheet, and `Done` on the receipt closes the whole thing.
struct PayView: View {
    @Environment(Wallet.self) private var wallet
    @Environment(\.theme) private var palette

    let card: Card
    let gateway: any ChargeGateway
    @Binding var isPresented: Bool

    @State private var chosen: Offer?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header.padding(.top, 30).padding(.bottom, 22)
                ForEach(Offer.all) { offer in
                    Button { chosen = offer } label: { row(offer) }
                        .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .background(palette.canvas)
            .navigationDestination(item: $chosen) { offer in
                CheckoutView(card: card, offer: offer, gateway: gateway) { isPresented = false }
                    .navigationBarBackButtonHidden(false)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Pay")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(palette.ink)
            Text("With \(card.name) ···· \(card.last4)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.inkTertiary)
        }
    }

    private func row(_ offer: Offer) -> some View {
        HStack(spacing: 14) {
            Image(systemName: offer.merchant.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.ink)
                .frame(width: 46, height: 46)
                .background(palette.accentSoft, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(offer.merchant.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Text(offer.merchant.category)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.inkTertiary)
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
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.inkTertiary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
