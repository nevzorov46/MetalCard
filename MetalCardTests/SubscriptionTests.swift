import Testing
import Foundation
@testable import MetalCard

@MainActor
@Suite("Subscriptions")
struct SubscriptionTests {

    private func subscribed(_ wallet: Wallet) throws -> (Subscription, Card) {
        let card = try #require(wallet.card("online"))
        let first = Receipt(id: "ch_first", amount: Plan.logicPro.price,
                            merchant: Merchant(name: "Logic Pro", category: "Subscription · apple.com",
                                               symbol: "pianokeys"),
                            last4: card.last4, completedAt: .now)
        return (wallet.subscribe(.logicPro, receipt: first, card: card), card)
    }

    @Test("Subscribing charges the first month and schedules the next")
    func subscribing() throws {
        let wallet = Wallet(store: nil)
        let usd = wallet.balance(in: .usd).minorUnits
        let (sub, _) = try subscribed(wallet)

        #expect(wallet.balance(in: .usd).minorUnits == usd - 499)
        #expect(sub.bills.count == 1)
        #expect(sub.nextPeriod == Subscription.period(after: Subscription.period(of: .now)))
        #expect(wallet.transactions.first?.id == "ch_first")
    }

    @Test("A month's key is the same however many times it is asked for")
    func keysArePerMonth() throws {
        let (sub, _) = try subscribed(Wallet(store: nil))
        #expect(sub.key(for: "2026-11") == sub.key(for: "2026-11"))
        #expect(sub.key(for: "2026-11") != sub.key(for: "2026-12"))
    }

    @Test("Billing a month twice charges it once, and the second run is a replay")
    func billingTwiceChargesOnce() async throws {
        let wallet = Wallet(store: nil)
        let (sub, _) = try subscribed(wallet)
        let gateway = PaymentGateway()
        let biller = Biller(wallet: wallet, gateway: gateway)
        let usd = wallet.balance(in: .usd).minorUnits
        let month = sub.nextPeriod

        let first = await biller.bill(sub, for: month)
        let again = await biller.bill(try #require(wallet.subscription(sub.id)), for: month)

        guard case .charged(let a) = first, case .replayed(let b) = again else {
            Issue.record("got \(first) then \(again)"); return
        }
        #expect(a.id == b.id)
        #expect(await gateway.charges == 1)
        #expect(wallet.balance(in: .usd).minorUnits == usd - 499)
        #expect(wallet.subscription(sub.id)?.bills.last?.retried == true)
        #expect(wallet.subscription(sub.id)?.nextPeriod == Subscription.period(after: month))
    }

    @Test("A lost answer during billing is retried under the month's key and charged once")
    func lostAnswerDuringBilling() async throws {
        let wallet = Wallet(store: nil)
        let (sub, _) = try subscribed(wallet)
        let gateway = PaymentGateway()
        let outcome = await Biller(wallet: wallet, gateway: gateway, loseFirstAnswer: true)
            .bill(sub, for: sub.nextPeriod)

        guard case .charged(let receipt) = outcome else { Issue.record("got \(outcome)"); return }
        #expect(receipt.wasReplay)
        #expect(await gateway.charges == 1)
    }

    @Test("A frozen card stops the month before any money moves")
    func frozenCardStopsBilling() async throws {
        let wallet = Wallet(store: nil)
        let (sub, card) = try subscribed(wallet)
        wallet.toggleFreeze(card)
        let gateway = PaymentGateway()

        let outcome = await Biller(wallet: wallet, gateway: gateway).bill(sub, for: sub.nextPeriod)

        #expect(outcome == .failed("Declined — card frozen"))
        #expect(await gateway.charges == 0)
        #expect(wallet.subscription(sub.id)?.status == .pastDue)
    }

    @Test("Subscriptions survive a relaunch")
    func persisted() throws {
        let store = WalletStore(url: FileManager.default.temporaryDirectory
            .appending(path: "wallet-\(UUID().uuidString).json"))
        let first = Wallet(store: store)
        let (sub, _) = try subscribed(first)
        first.cancel(sub.id)

        let second = Wallet(store: store)
        #expect(second.subscription(sub.id)?.status == .cancelled)
        #expect(second.subscription(sub.id)?.descriptor == "APPLE.COM/BILL")
    }

    @Test("December rolls over into January")
    func yearRollsOver() {
        #expect(Subscription.period(after: "2026-12") == "2027-01")
        #expect(Subscription.period(after: "2026-10") == "2026-11")
    }
}
