import SwiftUI

/// One subscription: what it costs, which card it takes, every month it has billed — and,
/// for the demo, the merchant's billing run, which can be pressed again for the same month
/// to show that a retry is not a second charge.
struct SubscriptionView: View {
    @Environment(Wallet.self) private var wallet
    @Environment(\.theme) private var palette

    let id: Subscription.ID
    let gateway: any ChargeGateway
    let onDone: () -> Void

    @State private var running = false
    @State private var outcome: BillOutcome?
    /// The month the last run billed, so it can be retried while the sheet is open.
    @State private var lastPeriod: String?
    @State private var confirmCancel = false

    private var subscription: Subscription? { wallet.subscription(id) }

    var body: some View {
        if let subscription {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(subscription).padding(.top, 30)
                    facts(subscription).padding(.top, 22)
                    if subscription.status != .cancelled {
                        billing(subscription).padding(.top, 26)
                    }
                    history(subscription).padding(.top, 26)
                    if subscription.status != .cancelled {
                        Button("Cancel subscription", role: .destructive) { confirmCancel = true }
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 28)
                            .confirmationDialog("Cancel \(subscription.plan)?", isPresented: $confirmCancel,
                                                titleVisibility: .visible) {
                                Button("Cancel subscription", role: .destructive) { wallet.cancel(id) }
                            } message: {
                                Text("No further months will be charged to \(cardName(subscription)).")
                            }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
            .background(palette.canvas)
            .animation(.smooth(duration: 0.3), value: subscription)
            .animation(.smooth(duration: 0.3), value: outcome)
            .sensoryFeedback(.success, trigger: outcome) { _, new in
                if case .charged = new { return true }
                if case .replayed = new { return true }
                return false
            }
        }
    }

    // MARK: Pieces

    private func header(_ s: Subscription) -> some View {
        HStack(spacing: 14) {
            Image(systemName: s.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(palette.ink)
                .frame(width: 52, height: 52)
                .background(palette.surface, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(s.plan).font(.system(size: 22, weight: .bold)).foregroundStyle(palette.ink)
                Text("\(s.price.formatted) / month").font(.system(size: 15)).foregroundStyle(palette.inkTertiary)
            }
            Spacer()
            status(s.status)
        }
    }

    private func status(_ status: Subscription.Status) -> some View {
        let (text, colour): (String, Color) = switch status {
        case .active:    ("Active", palette.positive)
        case .pastDue:   ("Past due", palette.ink)
        case .cancelled: ("Cancelled", palette.inkTertiary)
        }
        return Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(colour)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(colour.opacity(0.14), in: Capsule())
    }

    private func facts(_ s: Subscription) -> some View {
        VStack(spacing: 0) {
            fact("Card", cardName(s))
            divider
            fact("On your statement", s.descriptor, mono: true)
            divider
            if s.status == .cancelled {
                fact("Next payment", "None")
            } else {
                fact("Next payment", s.nextDate.formatted(date: .abbreviated, time: .omitted))
                if s.price.currency != .home {
                    divider
                    fact("In \(Currency.home.rawValue)", "≈ " + FX.convert(s.price, to: .home).formatted)
                }
            }
        }
        .padding(.horizontal, 16)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    /// The merchant's side, for the demo: run the next month, then run it again.
    private func billing(_ s: Subscription) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MERCHANT BILLING · DEMO")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(palette.inkTertiary)

            Text("The merchant charges the card on file each month, with no Face ID. Each month is billed under one key, \(Text("sub-\(s.id):month").font(.system(size: 13, design: .monospaced))), so billing a month twice charges it once.")
                .font(.system(size: 13))
                .foregroundStyle(palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                runButton("Bill \(Subscription.monthName(s.nextPeriod))", primary: true) {
                    await run(s, period: s.nextPeriod, loseFirstAnswer: true)
                }
                if let lastPeriod {
                    runButton("Retry \(Subscription.monthName(lastPeriod).components(separatedBy: " ").first ?? "")",
                              primary: false) {
                        await run(s, period: lastPeriod, loseFirstAnswer: false)
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }

            if let outcome {
                Text(describe(outcome))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            } else if running {
                Text("Charging — the first answer will be lost on purpose")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.inkTertiary)
            }
        }
    }

    private func runButton(_ title: String, primary: Bool, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 8) {
                if running && primary { ProgressView().tint(palette.onAccent) }
                Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(primary ? palette.onAccent : palette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(primary ? palette.accent : palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(running)
    }

    private func history(_ s: Subscription) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BILLING HISTORY")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(palette.inkTertiary)
            VStack(spacing: 0) {
                ForEach(Array(s.bills.reversed().enumerated()), id: \.element.id) { i, bill in
                    if i > 0 { divider }
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Subscription.monthName(bill.period))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(palette.ink)
                            if let failure = bill.failure {
                                Text(failure).font(.system(size: 13)).foregroundStyle(palette.ink)
                            } else if let charge = bill.chargeID {
                                Text(charge)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(palette.inkTertiary)
                                if bill.retried {
                                    Text("billed again · replayed · charged once")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(palette.positive)
                                }
                            }
                        }
                        Spacer()
                        Text(bill.chargeID == nil ? "—" : "−" + s.price.formatted)
                            .font(.system(size: 15, weight: .semibold).monospacedDigit())
                            .foregroundStyle(bill.chargeID == nil ? palette.inkTertiary : palette.ink)
                    }
                    .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 16)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func fact(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 14, weight: .medium)).foregroundStyle(palette.inkTertiary)
            Spacer(minLength: 12)
            Text(value)
                .font(mono ? .system(size: 13, weight: .medium, design: .monospaced) : .system(size: 14, weight: .semibold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 13)
    }

    private var divider: some View {
        Rectangle().fill(palette.inkTertiary.opacity(0.14)).frame(height: 1)
    }

    // MARK: Running

    private func run(_ s: Subscription, period: String, loseFirstAnswer: Bool) async {
        running = true
        outcome = nil
        let result = await Biller(wallet: wallet, gateway: gateway, loseFirstAnswer: loseFirstAnswer)
            .bill(s, for: period)
        outcome = result
        if case .failed = result {} else { lastPeriod = period }
        running = false
    }

    private func describe(_ outcome: BillOutcome) -> String {
        switch outcome {
        case .charged(let r):
            "Charged \(r.amount.formatted) · \(r.id)" + (r.wasReplay ? " — the first answer was lost, the retry got the same charge back." : "")
        case .replayed(let r):
            "Same month, same key: the gateway answered from its record. \(r.id), charged once."
        case .failed(let reason):
            reason
        }
    }

    private func cardName(_ s: Subscription) -> String {
        guard let card = wallet.card(s.cardID) else { return "—" }
        return "\(card.name) ···· \(card.last4)"
    }
}
