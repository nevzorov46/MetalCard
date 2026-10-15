import Foundation

// MARK: - The gateway

/// Stands in for the payment API. The case it models is a *successful* payment whose
/// response is lost: the money has moved, the phone does not know it, and the retry
/// that follows must not take it again.
actor PaymentGateway {

    /// On a real gateway: a table with a unique index on the key, kept for 24 hours.
    private var settled: [IdempotencyKey: Receipt] = [:]
    private var inFlight: Set<IdempotencyKey> = []
    private var responsesToDrop: Int
    private(set) var charges = 0

    init(responsesToDrop: Int = 0) {
        self.responsesToDrop = responsesToDrop
    }

    func authorize(_ request: ChargeRequest, last4: String) async throws -> Receipt {
        let key = request.idempotencyKey

        // Seen before, so this is a retry rather than a second purchase.
        if let known = settled[key] {
            try dropResponseIfAsked()
            return Receipt(id: known.id, amount: known.amount, merchant: known.merchant,
                           last4: known.last4, completedAt: known.completedAt, wasReplay: true)
        }

        // Claimed before the first `await`. An actor protects state at an instant, not
        // across a suspension — without this, two requests arriving together both find
        // an empty table and both charge.
        guard !inFlight.contains(key) else { throw PaymentError.duplicate }
        inFlight.insert(key)
        defer { inFlight.remove(key) }

        try await Task.sleep(for: .milliseconds(900))
        try Task.checkCancellation()

        guard request.amount.minorUnits <= Self.availableBalance(request.amount.currency) else {
            throw PaymentError.declined("Insufficient funds")
        }

        // Past this line the money has moved, whatever happens next.
        charges += 1
        let receipt = Receipt(id: "ch_" + String(UUID().uuidString.prefix(10)).lowercased(),
                              amount: request.amount, merchant: request.merchant,
                              last4: last4, completedAt: .now)
        settled[key] = receipt

        try dropResponseIfAsked()
        return receipt
    }

    /// Loses the response on the way back — a replay goes missing as easily as a first answer.
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

/// Retries under the same key, with a growing pause. Only a lost response is retried.
struct PaymentClient: Sendable {
    var gateway: any ChargeGateway
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
