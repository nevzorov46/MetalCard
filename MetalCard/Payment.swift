import Foundation

// MARK: - Money

/// Counted in minor units, never in a binary float: `0.1 + 0.2` is not `0.3` in Double,
/// and a ledger cannot afford that.
struct Money: Hashable, Sendable, Codable {
    var minorUnits: Int
    var currency: Currency

    var formatted: String { currency.format(minorUnits) }

    static func + (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "cannot add \(lhs.currency) to \(rhs.currency)")
        return Money(minorUnits: lhs.minorUnits + rhs.minorUnits, currency: lhs.currency)
    }
}

/// The exponent belongs to the currency — a yen has no subunit, a dinar has three.
/// Hard-coding two decimals is the bug that only appears once you cross a border.
enum Currency: String, Hashable, Sendable, CaseIterable, Codable {
    /// What the balance is shown in.
    static let home: Currency = .eur

    case eur = "EUR"
    case usd = "USD"
    case sgd = "SGD"
    case jpy = "JPY"

    var exponent: Int { self == .jpy ? 0 : 2 }

    func format(_ minorUnits: Int) -> String {
        let major = Decimal(minorUnits) / pow(Decimal(10), exponent)
        return major.formatted(.currency(code: rawValue).precision(.fractionLength(exponent)))
    }
}

// MARK: - Idempotency

/// One key per intent to pay, not per request — what lets the gateway tell a retry
/// apart from a second purchase.
struct IdempotencyKey: Hashable, Sendable, CustomStringConvertible {
    let value: String

    init(value: String = UUID().uuidString.lowercased()) { self.value = value }
    var description: String { value }
}

// MARK: - Request and receipt

struct Merchant: Hashable, Sendable, Codable {
    var name: String
    var category: String
    var symbol: String

    static let sample = Merchant(name: "Tamp & Grind", category: "Coffee · Singapore", symbol: "cup.and.saucer.fill")
}

struct ChargeRequest: Hashable, Sendable {
    var idempotencyKey: IdempotencyKey
    var cardID: Card.ID
    var amount: Money
    var merchant: Merchant
}

struct Receipt: Hashable, Sendable, Identifiable, Codable {
    var id: String
    var amount: Money
    var merchant: Merchant
    var last4: String
    var completedAt: Date
    /// Answered from the idempotency record rather than charged again.
    var wasReplay: Bool = false
}

// MARK: - Exchange

/// Fixed demo rates against the euro. Conversion goes through Decimal and rounds once,
/// at the end, to the target currency's minor unit.
enum FX {
    static let toEUR: [Currency: Decimal] = [.eur: 1, .usd: 0.92, .sgd: 0.69, .jpy: 0.0061]

    static func rate(from: Currency, to: Currency) -> Decimal {
        toEUR[from, default: 1] / toEUR[to, default: 1]
    }

    static func convert(_ money: Money, to currency: Currency) -> Money {
        guard money.currency != currency else { return money }
        let major = Decimal(money.minorUnits) / pow(Decimal(10), money.currency.exponent)
        let target = major * rate(from: money.currency, to: currency) * pow(Decimal(10), currency.exponent)
        var rounded = Decimal()
        var source = target
        NSDecimalRound(&rounded, &source, 0, .plain)
        return Money(minorUnits: NSDecimalNumber(decimal: rounded).intValue, currency: currency)
    }
}

// MARK: - Errors

enum PaymentError: Error, Equatable, Sendable {
    /// Caught on the device; never reaches the network.
    case cardFrozen
    case notAuthenticated
    /// The response never came back. Safe to retry under the same key.
    case network
    /// An answer, not a failure — retrying it would be wrong.
    case declined(String)
    /// The same key is already being charged.
    case duplicate
    /// No connection was made at all, so nothing was sent and nothing can have been charged.
    case unreachable

    var isRetriable: Bool { self == .network }

    var message: String {
        switch self {
        case .cardFrozen:      "This card is frozen"
        case .notAuthenticated: "Not confirmed"
        case .network:          "No answer from the bank"
        case .declined(let r):  r
        case .duplicate:        "Already paying"
        case .unreachable:      "Can't reach the gateway"
        }
    }
}
