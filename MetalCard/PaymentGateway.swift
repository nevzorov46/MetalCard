import Foundation

// MARK: - The gateway

/// Stands in for the payment API. It is an actor because it holds the one piece of state
/// that must never be read and written at the same time: the record of which keys have
/// already been charged.
///
/// The interesting case it models is not a failed payment. It is a *successful* payment
/// whose response is lost on the way back. The money has moved; the phone does not know it.
/// The client has no choice but to retry, and the retry must not take the money twice.
actor PaymentGateway {

    /// Charged keys and what they produced. On a real gateway this is a table with a
    /// unique index on the key, kept for 24 hours.
    private var settled: [IdempotencyKey: Receipt] = [:]

    /// Keys that are mid-charge. An actor keeps two calls from touching the state at the
    /// same *instant*, but it does not hold one out while the other is suspended at an
    /// `await`. Without claiming the key before that first suspension, two requests that
    /// arrive together both find an empty table and both take the money.
    private var inFlight: Set<IdempotencyKey> = []

    /// How many times to swallow the response before letting one through.
    /// Set it to 1 and the demo shows a retry; the money still moves only once.
    private var responsesToDrop: Int

    /// Every charge that actually moved money. Tests read this: after a retry storm
    /// of the same key it must still be 1.
    private(set) var charges = 0

    init(responsesToDrop: Int = 0) {
        self.responsesToDrop = responsesToDrop
    }

    func authorize(_ request: ChargeRequest, last4: String) async throws -> Receipt {
        let key = request.idempotencyKey

        // Replay. The key has been seen, so this is a retry, not a second purchase.
        if let known = settled[key] {
            try dropResponseIfAsked()
            return Receipt(id: known.id, amount: known.amount, merchant: known.merchant,
                           last4: known.last4, completedAt: known.completedAt, wasReplay: true)
        }

        // Claimed before the first `await`, released after the last one.
        guard !inFlight.contains(key) else { throw PaymentError.duplicate }
        inFlight.insert(key)
        defer { inFlight.remove(key) }

        try await Task.sleep(for: .milliseconds(900))
        try Task.checkCancellation()

        guard request.amount.minorUnits <= Self.availableBalance(request.amount.currency) else {
            // A decline is a decision, not a failure. Retrying it would be both pointless
            // and rude to the customer.
            throw PaymentError.declined("Insufficient funds")
        }

        // The charge happens here. Anything that goes wrong after this point has already
        // moved the money.
        charges += 1
        let receipt = Receipt(id: "ch_" + String(UUID().uuidString.prefix(10)).lowercased(),
                              amount: request.amount, merchant: request.merchant,
                              last4: last4, completedAt: .now)
        settled[key] = receipt

        try dropResponseIfAsked()
        return receipt
    }

    /// Loses the response on the way back. A replay can be lost just as easily as the
    /// first answer, so this sits on both paths.
    private func dropResponseIfAsked() throws {
        guard responsesToDrop > 0 else { return }
        responsesToDrop -= 1
        throw PaymentError.network
    }

    private static func availableBalance(_ currency: Currency) -> Int {
        switch currency {
        case .eur: 1_248_020
        case .usd: 342_15
        case .sgd: 1_890_40
        case .jpy: 86_400
        }
    }
}

// MARK: - The client

/// Retries, with the same key every time and a growing pause between attempts.
/// Only a lost response is retried — a decline is an answer, and asking again
/// would be both pointless and rude to the customer.
struct PaymentClient: Sendable {
    var gateway: PaymentGateway
    var maxAttempts = 3

    /// `onAttempt` reports which try is in flight, so the screen can say "Retrying".
    func pay(_ request: ChargeRequest, last4: String,
             onAttempt: @MainActor (Int) -> Void = { _ in }) async throws -> Receipt {
        var attempt = 1
        while true {
            try Task.checkCancellation()
            await onAttempt(attempt)
            do {
                return try await gateway.authorize(request, last4: last4)
            } catch let error as PaymentError where error.isRetriable && attempt < maxAttempts {
                attempt += 1
                try await Task.sleep(for: .milliseconds(400 * attempt))
            }
        }
    }
}
