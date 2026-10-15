import SwiftUI

/// What the sheet becomes once the payment has gone through. The number on it is the
/// charge id, not a pretty confirmation — it is the thing you quote when something is
/// wrong, so it is selectable and it stays on screen.
struct ReceiptView: View {
    @Environment(\.theme) private var palette

    let receipt: Receipt
    let cardName: String
    let onDone: () -> Void

    @State private var stamped = false

    var body: some View {
        VStack(spacing: 0) {
            stamp.padding(.top, 36)

            Text(receipt.amount.formatted)
                .font(.display(46))
                .foregroundStyle(palette.ink)
                .padding(.top, 20)

            Text(receipt.merchant.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.inkSecondary)
                .padding(.top, 4)

            VStack(spacing: 0) {
                row("Card", "\(cardName) ···· \(receipt.last4)")
                divider
                row("Charge", receipt.id, mono: true)
                divider
                row("Paid at", receipt.completedAt.formatted(date: .omitted, time: .standard))
                if receipt.amount.currency != .home {
                    divider
                    row("In \(Currency.home.rawValue)",
                        "≈ " + FX.convert(receipt.amount, to: .home).formatted + "  ·  "
                        + rateLine, mono: true)
                }
                if receipt.wasReplay {
                    divider
                    replayNote
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 4)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 24)
            .padding(.top, 28)

            Spacer(minLength: 20)

            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(palette.accent, in: RoundedRectangle(cornerRadius: 16))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 26)
        }
        .task {
            withAnimation(.bouncy(duration: 0.5, extraBounce: 0.2)) { stamped = true }
        }
    }

    private var stamp: some View {
        ZStack {
            Circle()
                .fill(palette.positive.opacity(0.14))
                .frame(width: 64, height: 64)
            Image(systemName: "checkmark")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(palette.positive)
        }
        .scaleEffect(stamped ? 1 : 0.6)
        .opacity(stamped ? 1 : 0)
    }

    private func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.inkTertiary)
            Spacer(minLength: 12)
            Text(value)
                .font(mono ? .system(size: 14, weight: .medium, design: .monospaced)
                           : .system(size: 14, weight: .semibold))
                .foregroundStyle(palette.ink)
                .textSelection(.enabled)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 13)
    }

    /// "1 SGD = 0.69 EUR", from the same table the conversion used.
    private var rateLine: String {
        let rate = FX.rate(from: receipt.amount.currency, to: .home)
        let text = rate.formatted(.number.precision(.fractionLength(rate < 0.01 ? 4 : 2)))
        return "1 \(receipt.amount.currency.rawValue) = \(text) \(Currency.home.rawValue)"
    }

    private var divider: some View {
        Rectangle()
            .fill(palette.inkTertiary.opacity(0.14))
            .frame(height: 1)
    }

    /// Only shown when the answer came back from the idempotency record. It is the one
    /// line on the receipt that says the retry did not cost anything.
    private var replayNote: some View {
        HStack(spacing: 9) {
            Image(systemName: "arrow.trianglehead.counterclockwise")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.accent)
            Text("The first answer was lost. Replayed from the idempotency key — charged once.")
                .font(.system(size: 13))
                .foregroundStyle(palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
    }
}
