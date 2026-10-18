import Foundation

// MARK: - What can be subscribed to

struct Plan: Hashable, Sendable {
    let name: String
    /// Who charges the card, as the customer would name them.
    let seller: String
    /// How the charge reads on a statement.
    let descriptor: String
    let domain: String
    let symbol: String
    let price: Money

    static let logicPro = Plan(name: "Logic Pro X", seller: "Apple", descriptor: "APPLE.COM/BILL",
                               domain: "apple.com", symbol: "pianokeys",
                               price: Money(minorUnits: 499, currency: .usd))
}

// MARK: - A subscription

/// Paid once by the customer, then charged by the merchant every month without asking.
/// Each month is billed under a key made from the subscription and the month, so the
/// merchant's billing system can retry a month as often as it likes — after a timeout,
/// a crash, a redeploy — and the month is still charged once.
struct Subscription: Identifiable, Hashable, Codable, Sendable {
    enum Status: String, Codable, Sendable { case active, pastDue, cancelled }

    struct Bill: Identifiable, Hashable, Codable, Sendable {
        var id: String { period }
        let period: String            // "2026-11"
        var chargeID: String?
        var date: Date
        /// The month was billed again and the gateway answered from its record.
        var retried = false
        var failure: String?
    }

    let id: String
    let plan: String
    let descriptor: String
    let domain: String
    let symbol: String
    let price: Money
    let cardID: Card.ID
    let started: Date
    var nextPeriod: String
    var status: Status = .active
    var bills: [Bill] = []

    var merchant: Merchant { Merchant(name: plan, category: "Subscription · \(domain)", symbol: symbol) }

    /// One key per subscription per month — not per attempt.
    func key(for period: String) -> IdempotencyKey { IdempotencyKey(value: "sub-\(id):\(period)") }

    /// When a month is charged: the same day of the month the subscription started.
    func date(of period: String) -> Date {
        let calendar = Calendar.current
        let parts = period.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return started }
        var c = calendar.dateComponents([.day, .hour, .minute], from: started)
        c.year = parts[0]
        c.month = parts[1]
        return calendar.date(from: c) ?? started
    }

    var nextDate: Date { date(of: nextPeriod) }

    // MARK: Months

    static func period(of date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    static func period(after period: String) -> String {
        let parts = period.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return period }
        let (year, month) = parts[1] == 12 ? (parts[0] + 1, 1) : (parts[0], parts[1] + 1)
        return String(format: "%04d-%02d", year, month)
    }

    static func monthName(_ period: String) -> String {
        let parts = period.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2,
              let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1]))
        else { return period }
        return date.formatted(.dateTime.month(.wide).year())
    }
}

// MARK: - The merchant's billing run

enum BillOutcome: Equatable {
    case charged(Receipt)
    /// The month had been charged already; the gateway answered from its record.
    case replayed(Receipt)
    case failed(String)
}

/// What a merchant's billing system does once a month: charge the card on file, with no
/// customer present and no Face ID. Running it twice for the same month is safe — that
/// is what the key is for.
@MainActor
struct Biller {
    let wallet: Wallet
    let gateway: any ChargeGateway
    /// Lose the answer to this run's first attempt, to show the retry.
    var loseFirstAnswer = false

    func bill(_ subscription: Subscription, for period: String) async -> BillOutcome {
        guard let card = wallet.card(subscription.cardID) else {
            return wallet.billFailed(subscription.id, period: period, reason: "Card no longer in the wallet")
        }
        // A frozen card is refused by the issuer — the wallet — before any money moves.
        guard !wallet.isFrozen(card) else {
            return wallet.billFailed(subscription.id, period: period, reason: "Declined — card frozen")
        }
        if loseFirstAnswer, let local = gateway as? PaymentGateway { await local.loseNextAnswer() }

        let request = ChargeRequest(idempotencyKey: subscription.key(for: period), cardID: card.id,
                                    amount: subscription.price, merchant: subscription.merchant)
        do {
            let receipt = try await PaymentClient(gateway: gateway).pay(request, last4: card.last4)
            return wallet.billSettled(subscription.id, period: period, receipt: receipt, card: card)
        } catch let error as PaymentError {
            return wallet.billFailed(subscription.id, period: period, reason: error.message)
        } catch {
            return wallet.billFailed(subscription.id, period: period, reason: PaymentError.network.message)
        }
    }
}
