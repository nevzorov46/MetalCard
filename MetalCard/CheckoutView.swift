import SwiftUI

/// The pay sheet. Merchant at the top, amount in the middle, the card you are paying with
/// at the bottom, and one button that changes its mind as the payment moves.
struct CheckoutView: View {
    @Environment(Wallet.self) private var wallet
    @Environment(\.theme) private var palette
    @Environment(\.dismiss) private var dismiss

    let card: Card
    @State private var checkout: Checkout

    init(card: Card, gateway: PaymentGateway) {
        self.card = card
        _checkout = State(initialValue: Checkout(amount: Money(minorUnits: 480, currency: .sgd),
                                                 merchant: .sample,
                                                 client: PaymentClient(gateway: gateway)))
    }

    private var frozen: Bool { wallet.isFrozen(card) }

    var body: some View {
        VStack(spacing: 0) {
            if case .approved(let receipt) = checkout.phase {
                ReceiptView(receipt: receipt, cardName: card.name) { dismiss() }
                    .transition(.opacity)
            } else {
                merchant.padding(.top, 34)
                amount.padding(.top, 26).padding(.bottom, 30)
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
    }

    // MARK: Pieces

    private var merchant: some View {
        VStack(spacing: 10) {
            Image(systemName: checkout.merchant.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.accent)
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

    private var payingWith: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 5)
                .fill(frozen ? palette.iceSurface : palette.accent)
                .frame(width: 38, height: 25)
                .overlay {
                    if frozen {
                        Image(systemName: "snowflake")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(palette.iceInk)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(card.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Text("•••• \(card.last4)")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(palette.inkTertiary)
            }
            Spacer()
            if frozen {
                Button("Unfreeze") { wallet.toggleFreeze(card) }
                    .font(.system(size: 14, weight: .semibold))
                    .tint(palette.accent)
            }
        }
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
            case .approved: dismiss()
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
