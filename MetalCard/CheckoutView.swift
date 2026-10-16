import SwiftUI

/// The pay sheet. Merchant at the top, amount in the middle, the card you are paying with
/// at the bottom, and one button that changes its mind as the payment moves.
struct CheckoutView: View {
    @Environment(Wallet.self) private var wallet
    @Environment(\.theme) private var palette
    @Environment(MotionTilt.self) private var motion
    let card: Card
    let onClose: () -> Void
    @State private var checkout: Checkout

    init(card: Card, offer: Offer, gateway: any ChargeGateway, onClose: @escaping () -> Void) {
        self.card = card
        self.onClose = onClose
        _checkout = State(initialValue: Checkout(amount: offer.amount,
                                                 merchant: offer.merchant,
                                                 client: PaymentClient(gateway: gateway)))
    }

    private var frozen: Bool { wallet.isFrozen(card) }

    var body: some View {
        VStack(spacing: 0) {
            if case .approved(let receipt) = checkout.phase {
                ReceiptView(receipt: receipt, cardName: card.name, onDone: onClose)
                    .transition(.opacity)
            } else {
                merchant.padding(.top, 28)
                amount.padding(.top, 18).padding(.bottom, 22)
                Divider().overlay(palette.inkTertiary.opacity(0.2)).padding(.horizontal, 24)
                payingWith.padding(.vertical, 18)
                Spacer(minLength: 0)
                status.padding(.horizontal, 24).padding(.bottom, 14)
                button.padding(.horizontal, 24).padding(.bottom, 26)
            }
        }
        .background(palette.canvas)
        .animation(.smooth(duration: 0.3), value: checkout.phase)
        .sensoryFeedback(.success, trigger: isApproved)
        .sensoryFeedback(.error, trigger: isFailed)
        // Choosing the merchant is the decision to pay: Face ID comes straight up, once the
        // push has settled. A frozen card waits for Unfreeze instead.
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            if checkout.phase == .ready && !frozen { checkout.pay(card: card, isFrozen: frozen) }
        }
        // The moment the payment is approved it becomes part of the wallet: balance
        // and history move together, before the receipt is even on screen.
        .onChange(of: checkout.phase) { _, phase in
            if case .approved(let receipt) = phase { wallet.record(receipt, card: card) }
        }
    }

    // MARK: Pieces

    private var merchant: some View {
        VStack(spacing: 10) {
            Image(systemName: checkout.merchant.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.ink)
                .frame(width: 56, height: 56)
                .background(palette.accentSoft, in: Circle())
            Text(checkout.merchant.name)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(palette.ink)
            Text(checkout.merchant.category)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.inkTertiary)
        }
    }

    private var amount: some View {
        Text(checkout.amount.formatted)
            .font(.display(52))
            .foregroundStyle(palette.ink)
            .contentTransition(.numericText())
    }

    /// The card itself, the same view as in the wallet: metal, a gift card's drawing, ice
    /// when it is frozen, and it follows the phone's tilt.
    private var payingWith: some View {
        VStack(spacing: 12) {
            CardView(card: card, tilt: motion.tilt, frost: frozen ? 1 : 0)
                .frame(width: 236)
                .animation(frozen ? .freeze : .thaw, value: frozen)
            if frozen {
                Button("Unfreeze to pay") {
                    wallet.toggleFreeze(card)
                    checkout.pay(card: card, isFrozen: false)
                }
                    .font(.system(size: 14, weight: .semibold))
                    .tint(palette.ink)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    /// One line under the button that explains whatever just happened.
    @ViewBuilder private var status: some View {
        switch checkout.phase {
        case .charging(let attempt) where attempt > 1:
            label("Retrying — the first answer never arrived", palette.inkTertiary)
        case .approved(let receipt):
            VStack(spacing: 4) {
                label("Paid \(receipt.amount.formatted) · \(receipt.id)", palette.positive)
                if receipt.wasReplay {
                    label("Replayed from the idempotency key — charged once", palette.inkTertiary)
                }
            }
        case .failed(let error):
            label(error.message, error == .cardFrozen ? palette.inkSecondary : palette.ink)
        default:
            Color.clear.frame(height: 1)
        }
    }

    private func label(_ text: String, _ colour: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(colour)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .transition(.opacity)
    }

    private var button: some View {
        Button {
            switch checkout.phase {
            case .approved: onClose()
            case .failed:   checkout.pay(card: card, isFrozen: frozen)
            default:        checkout.pay(card: card, isFrozen: frozen)
            }
        } label: {
            HStack(spacing: 8) {
                if checkout.phase.isBusy {
                    ProgressView().tint(palette.onAccent)
                }
                Text(buttonTitle)
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundStyle(palette.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(buttonColour, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(checkout.phase.isBusy || frozen)
        .opacity(frozen ? 0.45 : 1)
    }

    private var buttonTitle: String {
        switch checkout.phase {
        case .ready:        frozen ? "Card frozen" : "Pay \(checkout.amount.formatted)"
        case .confirming:   "Confirm with Face ID"
        case .charging:     "Paying"
        case .approved:     "Done"
        case .failed:       "Try again"
        }
    }

    private var buttonColour: Color {
        switch checkout.phase {
        case .approved: palette.positive
        default:        palette.accent
        }
    }

    private var isApproved: Bool { if case .approved = checkout.phase { true } else { false } }
    private var isFailed: Bool { if case .failed = checkout.phase { true } else { false } }
}
