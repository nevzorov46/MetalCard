import SwiftUI

/// Subscribing on a merchant's website. It is drawn as a page in a browser — light, plain,
/// the merchant's name and price and nothing of their branding — with the wallet offering
/// to pay in one tap: a saved card, Face ID, done. The first month is charged at once.
struct OnlineCheckoutView: View {
    @Environment(Wallet.self) private var wallet
    @Environment(\.theme) private var palette

    let plan: Plan
    let gateway: any ChargeGateway
    let onDone: () -> Void

    @State private var checkout: Checkout?
    @State private var subscribed: Subscription?

    /// The virtual card is the one for online subscriptions; any card will do if it is gone.
    private var card: Card? {
        wallet.card("online") ?? wallet.cards.first { !$0.isGift }
    }
    private var busy: Bool { checkout?.phase.isBusy ?? false }

    // The page is the merchant's, so it keeps a website's colours whatever the theme.
    private let paper = Color(hex: 0xFFFFFF)
    private let pageInk = Color(hex: 0x16161A)
    private let pageGrey = Color(hex: 0x6E6E78)
    private let pageRule = Color(hex: 0xE6E6EA)

    var body: some View {
        VStack(spacing: 0) {
            addressBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let subscribed {
                        done(subscribed)
                    } else {
                        offer
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(paper)
        }
        .background(paper)
        .animation(.smooth(duration: 0.35), value: subscribed)
        .animation(.smooth(duration: 0.25), value: checkout?.phase)
        .sensoryFeedback(.success, trigger: subscribed)
        .onChange(of: checkout?.phase) { _, phase in
            guard case .approved(let receipt) = phase, subscribed == nil, let card else { return }
            subscribed = wallet.subscribe(plan, receipt: receipt, card: card)
        }
    }

    // MARK: The browser

    private var addressBar: some View {
        HStack(spacing: 10) {
            Button("Done", action: onDone)
                .font(.system(size: 16, weight: .semibold))
                .tint(Color(hex: 0x0A66D6))
                .disabled(busy)
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 11, weight: .semibold))
                Text(plan.domain).font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(pageInk)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(Color(hex: 0xEFEFF2), in: RoundedRectangle(cornerRadius: 10))
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(pageGrey)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 10)
        .background(Color(hex: 0xF7F7F9))
        .overlay(alignment: .bottom) { pageRule.frame(height: 1) }
    }

    // MARK: The page

    private var offer: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Monthly subscription")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(pageGrey)
            Text(plan.name)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(pageInk)
                .padding(.top, 4)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(plan.price.formatted)
                    .font(.system(size: 26, weight: .semibold).monospacedDigit())
                Text("/ month")
                    .font(.system(size: 16))
                    .foregroundStyle(pageGrey)
            }
            .foregroundStyle(pageInk)
            .padding(.top, 10)
            Text("Billed monthly. Cancel anytime.")
                .font(.system(size: 14))
                .foregroundStyle(pageGrey)
                .padding(.top, 6)

            pageRule.frame(height: 1).padding(.vertical, 22)

            Text("Payment")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(pageInk)

            if let card {
                walletButton(card).padding(.top, 14)
                Text(note(for: card))
                    .font(.system(size: 13))
                    .foregroundStyle(failed ? Color(hex: 0xB3261E) : pageGrey)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }

            Text("By subscribing you authorise \(plan.seller) to charge your card \(plan.price.formatted) every month until you cancel. It appears on your statement as \(plan.descriptor).")
                .font(.system(size: 12))
                .foregroundStyle(pageGrey)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 22)
        }
    }

    /// The wallet's one-tap button: the saved card, and Face ID instead of a form.
    private func walletButton(_ card: Card) -> some View {
        Button {
            if checkout == nil {
                checkout = Checkout(amount: plan.price, merchant: Merchant(name: plan.name,
                                                                           category: "Subscription · \(plan.domain)",
                                                                           symbol: plan.symbol),
                                    client: PaymentClient(gateway: gateway))
            }
            checkout?.pay(card: card, isFrozen: wallet.isFrozen(card))
        } label: {
            HStack(spacing: 12) {
                MiniCard(card: card).frame(width: 46, height: 29)
                VStack(alignment: .leading, spacing: 2) {
                    Text(busy ? progress : "Pay with Wallet")
                        .font(.system(size: 16, weight: .semibold))
                    Text("\(card.name) ···· \(card.last4)")
                        .font(.system(size: 13).monospacedDigit())
                        .opacity(0.7)
                }
                Spacer()
                if busy {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "faceid").font(.system(size: 20, weight: .medium))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 64)
            .background(Color(hex: 0x16161A), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func done(_ subscription: Subscription) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color(hex: 0x1F8A4C))
            Text("You're subscribed")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(pageInk)
                .padding(.top, 14)
            Text("\(subscription.plan) · \(subscription.price.formatted) / month")
                .font(.system(size: 16))
                .foregroundStyle(pageGrey)
                .padding(.top, 6)
            pageRule.frame(height: 1).padding(.vertical, 22)
            row("Next payment", subscription.nextDate.formatted(date: .abbreviated, time: .omitted))
            row("Card", "\(card?.name ?? "") ···· \(card?.last4 ?? "")")
            if let first = subscription.bills.first?.chargeID { row("Charge", first, mono: true) }
            Text("It is in your wallet under Subscriptions. You can cancel it there, or freeze the card to stop it.")
                .font(.system(size: 13))
                .foregroundStyle(pageGrey)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
            Button(action: onDone) {
                Text("Back to wallet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(hex: 0x16161A), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.top, 26)
        }
    }

    private func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(pageGrey)
            Spacer()
            Text(value)
                .font(mono ? .system(size: 14, design: .monospaced) : .system(size: 15, weight: .semibold))
                .foregroundStyle(pageInk)
        }
        .font(.system(size: 15))
        .padding(.vertical, 8)
    }

    // MARK: State

    private var failed: Bool { if case .failed = checkout?.phase { true } else { false } }

    private var progress: String {
        switch checkout?.phase {
        case .confirming:                  "Confirm with Face ID"
        case .charging(let n) where n > 1: "Retrying…"
        default:                           "Paying…"
        }
    }

    private func note(for card: Card) -> String {
        if case .failed(let error) = checkout?.phase { return error.message + ". Tap to try again." }
        if case .charging(let n) = checkout?.phase, n > 1 { return "No answer — retrying with the same key." }
        return "Saved in your wallet. No card number to type."
    }
}

/// A card at the size of a payment-method icon.
struct MiniCard: View {
    @Environment(\.theme) private var palette
    let card: Card

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(card.art?.base ?? palette.colourway(card.style).base)
            .overlay {
                if let art = card.art { CardArtView(art: art).clipShape(RoundedRectangle(cornerRadius: 4)) }
            }
            // A light edge and the last digits, so a dark card still reads on a dark button.
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.white.opacity(0.45), lineWidth: 1))
            .overlay(alignment: .bottomTrailing) {
                Text(card.last4)
                    .font(.system(size: 7, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(3)
            }
    }
}
