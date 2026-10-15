import Foundation
import LocalAuthentication

// MARK: - Who confirms the payment

/// Behind a protocol so the flow can be tested without a face.
protocol Authenticator: Sendable {
    func confirm(reason: String) async throws
}

struct BiometricAuthenticator: Authenticator {
    func confirm(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw PaymentError.notAuthenticated
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            guard ok else { throw PaymentError.notAuthenticated }
        } catch {
            throw PaymentError.notAuthenticated
        }
    }
}

// MARK: - The flow

/// One checkout, from the moment the sheet opens to the receipt.
///
/// The idempotency key is made once, here, and survives every retry inside `pay()`.
/// Tapping Pay again after a failure reuses it too — the customer's intent has not
/// changed, so neither should the key.
@MainActor
@Observable
final class Checkout {

    enum Phase: Equatable {
        case ready
        case confirming
        case charging(attempt: Int)
        case approved(Receipt)
        case failed(PaymentError)

        var isBusy: Bool {
            switch self {
            case .confirming, .charging: true
            default: false
            }
        }
    }

    let amount: Money
    let merchant: Merchant
    private(set) var phase: Phase = .ready
    private(set) var key = IdempotencyKey()

    private let client: PaymentClient
    private let authenticator: Authenticator
    private var task: Task<Void, Never>?

    init(amount: Money, merchant: Merchant,
         client: PaymentClient, authenticator: Authenticator = BiometricAuthenticator()) {
        self.amount = amount
        self.merchant = merchant
        self.client = client
        self.authenticator = authenticator
    }

    func pay(card: Card, isFrozen: Bool) {
        guard !phase.isBusy else { return }

        // Caught on the device. A frozen card never reaches the network — that is the
        // whole point of freezing it.
        guard !isFrozen else { phase = .failed(.cardFrozen); return }

        let request = ChargeRequest(idempotencyKey: key, cardID: card.id,
                                    amount: amount, merchant: merchant)

        // Set before the task starts, not inside it. A `Task` body does not run until the
        // next turn of the main actor, so a second tap arriving in the same turn would
        // still read `.ready` and start a second payment.
        phase = .confirming

        task = Task {
            do {
                try await authenticator.confirm(reason: "Pay \(amount.formatted) to \(merchant.name)")
                let receipt = try await client.pay(request, last4: card.last4) { attempt in
                    self.phase = .charging(attempt: attempt)
                }
                phase = .approved(receipt)
            } catch is CancellationError {
                phase = .ready
            } catch let error as PaymentError {
                phase = .failed(error)
            } catch {
                phase = .failed(.network)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = .ready
    }

    /// Start over with a new intent — a new key, because this is a new purchase.
    func reset() {
        cancel()
        key = IdempotencyKey()
    }
}
