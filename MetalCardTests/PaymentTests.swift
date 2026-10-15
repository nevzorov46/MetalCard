import Testing
import Foundation
@testable import MetalCard

// MARK: - Money

@Suite("Money")
struct MoneyTests {

    @Test("A euro amount keeps two decimals")
    func euroFormatting() {
        let price = Money(minorUnits: 480, currency: .eur)
        #expect(price.formatted.contains("4.80") || price.formatted.contains("4,80"))
    }

    @Test("Yen has no subunit, so it is never shown with decimals")
    func yenHasNoDecimals() {
        let price = Money(minorUnits: 4800, currency: .jpy)
        #expect(Currency.jpy.exponent == 0)
        #expect(!price.formatted.contains("."))
    }

    @Test("Adding stays exact where a Double would drift")
    func additionIsExact() {
        // 0.1 + 0.2 in Double is 0.30000000000000004. In minor units it is 30.
        let total = Money(minorUnits: 10, currency: .eur) + Money(minorUnits: 20, currency: .eur)
        #expect(total.minorUnits == 30)
    }
}

// MARK: - Idempotency

@Suite("Idempotency")
struct IdempotencyTests {

    private func request(_ key: IdempotencyKey, minorUnits: Int = 480) -> ChargeRequest {
        ChargeRequest(idempotencyKey: key, cardID: "everyday",
                      amount: Money(minorUnits: minorUnits, currency: .sgd),
                      merchant: .sample)
    }

    @Test("A lost response is retried, and the money moves exactly once")
    func retryDoesNotDoubleCharge() async throws {
        // The gateway charges, then drops the response. The client has no way to know
        // the charge went through — it can only retry with the same key.
        let gateway = PaymentGateway(responsesToDrop: 1)
        let client = PaymentClient(gateway: gateway)

        let receipt = try await client.pay(request(IdempotencyKey()), last4: "4821")

        #expect(receipt.wasReplay)
        let charges = await gateway.charges
        #expect(charges == 1)
    }

    @Test("Two taps on Pay with the same intent are one purchase")
    func sameKeyTwiceIsOnePurchase() async throws {
        let gateway = PaymentGateway()
        let client = PaymentClient(gateway: gateway)
        let key = IdempotencyKey()

        let first = try await client.pay(request(key), last4: "4821")
        let second = try await client.pay(request(key), last4: "4821")

        #expect(first.id == second.id)
        #expect(second.wasReplay)
        let charges = await gateway.charges
        #expect(charges == 1)
    }

    @Test("A new intent gets a new key, and is charged on its own")
    func newKeyIsANewPurchase() async throws {
        let gateway = PaymentGateway()
        let client = PaymentClient(gateway: gateway)

        _ = try await client.pay(request(IdempotencyKey()), last4: "4821")
        _ = try await client.pay(request(IdempotencyKey()), last4: "4821")

        let charges = await gateway.charges
        #expect(charges == 2)
    }

    @Test("A decline is an answer, not a failure — it is never retried")
    func declineIsNotRetried() async throws {
        let gateway = PaymentGateway()
        let client = PaymentClient(gateway: gateway)
        // More than the SGD balance.
        let tooMuch = request(IdempotencyKey(), minorUnits: 999_999_99)

        await #expect(throws: PaymentError.declined("Insufficient funds")) {
            try await client.pay(tooMuch, last4: "4821")
        }
        let charges = await gateway.charges
        #expect(charges == 0)
    }

    @Test("Giving up still leaves one charge behind, not three")
    func exhaustedRetriesChargeOnce() async throws {
        let gateway = PaymentGateway(responsesToDrop: 5)
        let client = PaymentClient(gateway: gateway, maxAttempts: 3)

        await #expect(throws: PaymentError.network) {
            try await client.pay(request(IdempotencyKey()), last4: "4821")
        }
        // Attempts two and three replayed the record instead of charging again.
        let charges = await gateway.charges
        #expect(charges == 1)
    }
}

// MARK: - The checkout flow

private struct AlwaysConfirms: Authenticator {
    func confirm(reason: String) async throws {}
}

private struct NeverConfirms: Authenticator {
    func confirm(reason: String) async throws { throw PaymentError.notAuthenticated }
}

@Suite("Checkout")
@MainActor
struct CheckoutTests {

    private func checkout(_ auth: Authenticator, gateway: PaymentGateway = PaymentGateway()) -> Checkout {
        Checkout(amount: Money(minorUnits: 480, currency: .sgd), merchant: .sample,
                 client: PaymentClient(gateway: gateway), authenticator: auth)
    }

    @Test("A frozen card is stopped on the device, before any network call")
    func frozenCardNeverReachesTheNetwork() async throws {
        let gateway = PaymentGateway()
        let flow = checkout(AlwaysConfirms(), gateway: gateway)

        flow.pay(card: Card.samples[0], isFrozen: true)
        try await Task.sleep(for: .milliseconds(50))

        #expect(flow.phase == .failed(.cardFrozen))
        let charges = await gateway.charges
        #expect(charges == 0)
    }

    @Test("A dismissed Face ID leaves the money where it is")
    func declinedBiometricsDoesNotCharge() async throws {
        let gateway = PaymentGateway()
        let flow = checkout(NeverConfirms(), gateway: gateway)

        flow.pay(card: Card.samples[0], isFrozen: false)
        try await Task.sleep(for: .milliseconds(80))

        #expect(flow.phase == .failed(.notAuthenticated))
        let charges = await gateway.charges
        #expect(charges == 0)
    }

    @Test("Paying again after a failure keeps the same key — it is the same purchase")
    func retryAfterFailureKeepsTheKey() async throws {
        let flow = checkout(NeverConfirms())
        let key = flow.key

        flow.pay(card: Card.samples[0], isFrozen: false)
        try await Task.sleep(for: .milliseconds(80))
        #expect(flow.key == key)
    }

    @Test("Starting over is a new purchase, so it gets a new key")
    func resetMakesANewKey() {
        let flow = checkout(AlwaysConfirms())
        let key = flow.key
        flow.reset()
        #expect(flow.key != key)
    }

    @Test("Two requests racing on one key: only one of them charges")
    func concurrentDuplicatesChargeOnce() async throws {
        let gateway = PaymentGateway()
        let client = PaymentClient(gateway: gateway)
        let key = IdempotencyKey()
        let request = ChargeRequest(idempotencyKey: key, cardID: "everyday",
                                    amount: Money(minorUnits: 480, currency: .sgd),
                                    merchant: .sample)

        // Both are in the air before either has written anything down.
        async let first = try? await client.pay(request, last4: "4821")
        async let second = try? await client.pay(request, last4: "4821")
        _ = await (first, second)

        let charges = await gateway.charges
        #expect(charges == 1)
    }

    @Test("A second tap while the first is in flight is ignored")
    func doubleTapIsIgnored() async throws {
        let gateway = PaymentGateway()
        let flow = checkout(AlwaysConfirms(), gateway: gateway)

        flow.pay(card: Card.samples[0], isFrozen: false)
        flow.pay(card: Card.samples[0], isFrozen: false)
        try await Task.sleep(for: .milliseconds(1_400))

        let charges = await gateway.charges
        #expect(charges == 1)
    }
}

// MARK: - The card itself

@Suite("Card")
struct CardTests {

    @Test("The number is shown in groups of four")
    func numberIsGrouped() {
        let card = Card.samples[0]
        #expect(card.groupedNumber == "4000 8210 9335 4821")
    }

    @Test("Only the last four digits are ever used for display")
    func lastFour() {
        #expect(Card.samples[0].last4 == "4821")
    }

    @Test("The sample numbers fail the Luhn check on purpose")
    func samplesAreNotRealCardNumbers() {
        for card in Card.samples {
            #expect(!passesLuhn(card.number), "\(card.name) looks like a real PAN")
        }
    }

    /// The check a real card number passes. Used here to prove these do not.
    private func passesLuhn(_ number: String) -> Bool {
        let digits = number.compactMap(\.wholeNumberValue)
        guard digits.count == 16 else { return false }
        let sum = digits.reversed().enumerated().reduce(0) { total, pair in
            let (index, digit) = pair
            guard index.isMultiple(of: 2) == false else { return total + digit }
            let doubled = digit * 2
            return total + (doubled > 9 ? doubled - 9 : doubled)
        }
        return sum.isMultiple(of: 10)
    }
}
