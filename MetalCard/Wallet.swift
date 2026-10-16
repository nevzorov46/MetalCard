import Foundation
import SwiftUI

/// Shared state: the cards, which are frozen, the balances and what has been paid.
/// Everything a payment changes lives here, so the home screen, the receipt and the
/// list of transactions cannot disagree about what just happened.
@Observable
final class Wallet {
    private(set) var cards = Card.samples
    var frozen: Set<Card.ID> = []
    private(set) var transactions: [Transaction] = []
    /// Minor units per currency. The same four the gateway holds.
    private(set) var balances: [Currency: Int] = [:]
    /// What is left on each gift card. Kept apart from the balances above: a gift card's
    /// money was paid for already, and it does not count towards the total.
    private(set) var giftBalances: [Card.ID: Money] = [:]
    private(set) var subscriptions: [Subscription] = []

    private let store: WalletStore?

    init(store: WalletStore? = .standard) {
        self.store = store
        if let saved = store?.load() {
            frozen = saved.frozen
            transactions = saved.transactions
            balances = saved.balances
            // Older files have neither; they start from the samples.
            cards = saved.cards ?? Card.samples
            giftBalances = saved.giftBalances ?? Self.openingGiftBalances
            subscriptions = saved.subscriptions ?? []
        } else {
            transactions = Transaction.samples
            balances = Self.openingBalances
            giftBalances = Self.openingGiftBalances
        }
    }

    static let openingBalances: [Currency: Int] = [.eur: 1_248_020, .usd: 34_215, .sgd: 189_040, .jpy: 86_400]
    static let openingGiftBalances: [Card.ID: Money] = [
        "gift-birthday": Money(minorUnits: 15_000, currency: .sgd),
        "gift-winter":   Money(minorUnits: 60_000, currency: .sgd),
        "gift-weekend":  Money(minorUnits: 8_000, currency: .sgd)
    ]

    func card(_ id: Card.ID) -> Card? { cards.first { $0.id == id } }
    func isFrozen(_ card: Card) -> Bool { frozen.contains(card.id) }

    func toggleFreeze(_ card: Card) {
        if frozen.contains(card.id) { frozen.remove(card.id) } else { frozen.insert(card.id) }
        persist()
    }

    // MARK: Money

    func balance(in currency: Currency) -> Money {
        Money(minorUnits: balances[currency] ?? 0, currency: currency)
    }

    /// Everything, converted to the home currency.
    var total: Money {
        let sum = Currency.allCases.reduce(0) { acc, currency in
            acc + FX.convert(balance(in: currency), to: .home).minorUnits
        }
        return Money(minorUnits: sum, currency: .home)
    }

    // MARK: Gift cards

    func giftBalance(of card: Card) -> Money? { giftBalances[card.id] }

    /// A gift card can only spend what is on it. Other cards leave that to the gateway.
    func canPay(_ amount: Money, with card: Card) -> Bool {
        guard card.isGift, let left = giftBalances[card.id] else { return true }
        return FX.convert(amount, to: left.currency).minorUnits <= left.minorUnits
    }

    // MARK: Subscriptions

    /// The first month, paid by the customer with Face ID, starts the subscription.
    @discardableResult
    func subscribe(_ plan: Plan, receipt: Receipt, card: Card) -> Subscription {
        record(receipt, card: card)
        let period = Subscription.period(of: receipt.completedAt)
        let subscription = Subscription(
            id: String(UUID().uuidString.prefix(8)).lowercased(),
            plan: plan.name, descriptor: plan.descriptor, domain: plan.domain, symbol: plan.symbol,
            price: plan.price, cardID: card.id, started: receipt.completedAt,
            nextPeriod: Subscription.period(after: period),
            bills: [.init(period: period, chargeID: receipt.id, date: receipt.completedAt)])
        subscriptions.insert(subscription, at: 0)
        persist()
        return subscription
    }

    func subscription(_ id: Subscription.ID) -> Subscription? { subscriptions.first { $0.id == id } }

    func cancel(_ id: Subscription.ID) {
        guard let i = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        subscriptions[i].status = .cancelled
        persist()
    }

    /// A month went through. If the month already has this charge, the gateway replayed
    /// it: marked as retried, and — because `record` is keyed by charge id — not debited
    /// a second time.
    func billSettled(_ id: Subscription.ID, period: String, receipt: Receipt, card: Card) -> BillOutcome {
        guard let i = subscriptions.firstIndex(where: { $0.id == id }) else { return .failed("No such subscription") }
        record(receipt, card: card)
        if let b = subscriptions[i].bills.firstIndex(where: { $0.period == period }),
           subscriptions[i].bills[b].chargeID == receipt.id {
            subscriptions[i].bills[b].retried = true
            persist()
            return .replayed(receipt)
        }
        let bill = Subscription.Bill(period: period, chargeID: receipt.id, date: receipt.completedAt)
        if let b = subscriptions[i].bills.firstIndex(where: { $0.period == period }) {
            subscriptions[i].bills[b] = bill            // a failed month, paid on a later run
        } else {
            subscriptions[i].bills.append(bill)
        }
        subscriptions[i].status = .active
        if period == subscriptions[i].nextPeriod {
            subscriptions[i].nextPeriod = Subscription.period(after: period)
        }
        persist()
        return .charged(receipt)
    }

    func billFailed(_ id: Subscription.ID, period: String, reason: String) -> BillOutcome {
        guard let i = subscriptions.firstIndex(where: { $0.id == id }) else { return .failed(reason) }
        if !subscriptions[i].bills.contains(where: { $0.period == period && $0.chargeID != nil }) {
            subscriptions[i].bills.removeAll { $0.period == period }
            subscriptions[i].bills.append(.init(period: period, chargeID: nil, date: .now, failure: reason))
            subscriptions[i].status = .pastDue
        }
        persist()
        return .failed(reason)
    }

    /// A payment has gone through. Debit what paid for it — the gift card's own balance,
    /// or the balance in the charge's currency — and put the transaction at the top.
    /// Called once per receipt: a replayed receipt carries the same id as the first, and a
    /// second record of it would be the double charge the gateway went to such trouble
    /// to avoid.
    func record(_ receipt: Receipt, card: Card) {
        guard !transactions.contains(where: { $0.id == receipt.id }) else { return }
        if card.isGift, let left = giftBalances[card.id] {
            let spent = FX.convert(receipt.amount, to: left.currency)
            giftBalances[card.id] = Money(minorUnits: left.minorUnits - spent.minorUnits, currency: left.currency)
        } else {
            balances[receipt.amount.currency, default: 0] -= receipt.amount.minorUnits
        }
        transactions.insert(Transaction(receipt: receipt, card: card), at: 0)
        persist()
    }

    private func persist() {
        store?.save(WalletSnapshot(frozen: frozen, transactions: transactions, balances: balances,
                                   cards: cards, giftBalances: giftBalances, subscriptions: subscriptions))
    }
}

// MARK: - Transactions

struct Transaction: Identifiable, Hashable, Codable {
    let id: String
    var merchant: Merchant
    var amount: Money
    var cardName: String
    var last4: String
    var date: Date
    var incoming = false
    /// Which card paid, when this came from a payment made here.
    var cardID: Card.ID? = nil
    /// The receipt, when this came from a payment made here. The seeded history has none.
    var receipt: Receipt?

    init(receipt: Receipt, card: Card) {
        id = receipt.id
        merchant = receipt.merchant
        amount = receipt.amount
        cardName = card.name
        cardID = card.id
        last4 = receipt.last4
        date = receipt.completedAt
        self.receipt = receipt
    }

    init(id: String, merchant: Merchant, amount: Money, cardName: String, last4: String,
         daysAgo: Double, incoming: Bool = false) {
        self.id = id
        self.merchant = merchant
        self.amount = amount
        self.cardName = cardName
        self.last4 = last4
        self.date = Date(timeIntervalSinceNow: -daysAgo * 86_400)
        self.incoming = incoming
    }

    var title: String { merchant.name }
    var symbol: String { merchant.symbol }

    var subtitle: String {
        let when: String
        if Calendar.current.isDateInToday(date) { when = "Today" }
        else if Calendar.current.isDateInYesterday(date) { when = "Yesterday" }
        else { when = date.formatted(.dateTime.weekday(.abbreviated)) }
        return "\(when) · \(cardName)"
    }

    var signedAmount: String {
        (incoming ? "+" : "−") + amount.formatted
    }

    static let samples: [Transaction] = [
        Transaction(id: "seed-1", merchant: Merchant(name: "Anna Petrova", category: "Transfer", symbol: "arrow.down.left"),
                    amount: Money(minorUnits: 12_000, currency: .eur), cardName: "Transfer", last4: "", daysAgo: 0.2, incoming: true),
        Transaction(id: "seed-2", merchant: Merchant(name: "Metro Taxi", category: "Travel", symbol: "car.fill"),
                    amount: Money(minorUnits: 1_840, currency: .eur), cardName: "Travel", last4: "4418", daysAgo: 1.1),
        Transaction(id: "seed-3", merchant: Merchant(name: "Green Basket", category: "Groceries", symbol: "basket.fill"),
                    amount: Money(minorUnits: 3_615, currency: .eur), cardName: "Everyday", last4: "4821", daysAgo: 1.4),
        Transaction(id: "seed-4", merchant: Merchant(name: "Lumen Streaming", category: "Subscription", symbol: "play.rectangle.fill"),
                    amount: Money(minorUnits: 999, currency: .usd), cardName: "Online", last4: "5566", daysAgo: 3.0)
    ]
}

// MARK: - Persistence

struct WalletSnapshot: Codable {
    var frozen: Set<Card.ID>
    var transactions: [Transaction]
    var balances: [Currency: Int]
    var cards: [Card]?
    var giftBalances: [Card.ID: Money]?
    var subscriptions: [Subscription]?
}

/// A JSON file in Application Support. Small enough that rewriting it whole is fine.
struct WalletStore {
    let url: URL

    static let standard: WalletStore? = {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appending(path: "MetalCard", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return WalletStore(url: dir.appending(path: "wallet.json"))
    }()

    func load() -> WalletSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.wallet.decode(WalletSnapshot.self, from: data)
    }

    func save(_ snapshot: WalletSnapshot) {
        guard let data = try? JSONEncoder.wallet.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

extension JSONEncoder {
    static let wallet: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

extension JSONDecoder {
    static let wallet: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
