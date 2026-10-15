import Foundation

// MARK: - Money

/// Money is counted in minor units — cents, not euros — and never in a binary float.
/// `0.1 + 0.2` is not `0.3` in Double, and a payments ledger cannot afford that.
struct Money: Hashable, Sendable {
    var minorUnits: Int
    var currency: Currency

    var formatted: String { currency.format(minorUnits) }

    static func + (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "cannot add \(lhs.currency) to \(rhs.currency)")
        return Money(minorUnits: lhs.minorUnits + rhs.minorUnits, currency: lhs.currency)
    }
}

/// The exponent is per currency: a yen has no subunit, a dinar has three.
/// Hard-coding two decimals is the bug that only shows up once you cross a border.
enum Currency: String, Hashable, Sendable, CaseIterable {
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

/// One key per *intent to pay*, not per request. Every retry of the same intent carries
/// the same key, which is what lets the gateway tell a retry apart from a second purchase.
struct IdempotencyKey: Hashable, Sendable, CustomStringConvertible {
    let value: String

    init(value: String = UUID().uuidString.lowercased()) { self.value = value }
    var description: String { value }
}

// MARK: - Request and receipt

struct Merchant: Hashable, Sendable {
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

struct Receipt: Hashable, Sendable, Identifiable {
    var id: String
    var amount: Money
    var merchant: Merchant
    var last4: String
    var completedAt: Date
    /// True when the gateway answered from its idempotency record rather than charging again.
    var wasReplay: Bool = false
}

// MARK: - Errors

enum PaymentError: Error, Equatable, Sendable {
    /// The card is frozen. Caught on the device — this never reaches the network.
    case cardFrozen
    /// Face ID was dismissed or failed.
    case notAuthenticated
    /// The response never came back. Safe to retry with the same key.
    case network
    /// The gateway said no. Retrying is pointless and would be wrong.
    case declined(String)
    /// The same key is already being charged. The gateway refuses the second one
    /// rather than racing it.
    case duplicate

    var isRetriable: Bool { self == .network }

    var message: String {
        switch self {
        case .cardFrozen:      "This card is frozen"
        case .notAuthenticated: "Not confirmed"
        case .network:          "No answer from the bank"
        case .declined(let r):  r
        case .duplicate:        "Already paying"
        }
    }
}
