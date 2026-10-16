import Testing
import Foundation
import SwiftUI
@testable import MetalCard

// MARK: - Exchange

@Suite("Exchange")
struct FXTests {

    @Test("Converting to the same currency changes nothing")
    func identity() {
        let m = Money(minorUnits: 480, currency: .sgd)
        #expect(FX.convert(m, to: .sgd) == m)
    }

    @Test("SGD 4.80 is about €3.31 at the table's rate")
    func singaporeToEuro() {
        let m = FX.convert(Money(minorUnits: 480, currency: .sgd), to: .eur)
        #expect(m.currency == .eur)
        #expect(m.minorUnits == 331)
    }

    @Test("Yen has no minor unit, so a conversion into it rounds to whole yen")
    func euroToYen() {
        let m = FX.convert(Money(minorUnits: 100, currency: .eur), to: .jpy)
        #expect(m.currency == .jpy)
        #expect(m.minorUnits == 164)
    }

    @Test("A rate and its inverse multiply back to one")
    func inverse() {
        let there = FX.rate(from: .usd, to: .sgd)
        let back = FX.rate(from: .sgd, to: .usd)
        let product = NSDecimalNumber(decimal: there * back).doubleValue
        #expect(abs(product - 1) < 1e-9)
    }
}

// MARK: - The wallet

@MainActor
@Suite("Wallet")
struct WalletTests {

    private func receipt(id: String = "ch_test", minor: Int = 480, currency: Currency = .sgd) -> Receipt {
        Receipt(id: id, amount: Money(minorUnits: minor, currency: currency),
                merchant: .sample, last4: "4821", completedAt: .now)
    }

    @Test("A payment debits its own currency and goes to the top of the list")
    func recordDebitsAndInserts() {
        let wallet = Wallet(store: nil)
        let before = wallet.balance(in: .sgd).minorUnits
        let count = wallet.transactions.count

        wallet.record(receipt(), card: Card.samples[0])

        #expect(wallet.balance(in: .sgd).minorUnits == before - 480)
        #expect(wallet.transactions.count == count + 1)
        #expect(wallet.transactions.first?.id == "ch_test")
        #expect(wallet.transactions.first?.receipt != nil)
    }

    @Test("Other currencies are untouched by a payment in one of them")
    func otherBalancesStay() {
        let wallet = Wallet(store: nil)
        let eur = wallet.balance(in: .eur).minorUnits
        wallet.record(receipt(), card: Card.samples[0])
        #expect(wallet.balance(in: .eur).minorUnits == eur)
    }

    @Test("The same receipt recorded twice counts once")
    func replayIsNotRecordedTwice() {
        let wallet = Wallet(store: nil)
        let before = wallet.balance(in: .sgd).minorUnits
        wallet.record(receipt(), card: Card.samples[0])
        wallet.record(receipt(), card: Card.samples[0])
        #expect(wallet.balance(in: .sgd).minorUnits == before - 480)
        #expect(wallet.transactions.filter { $0.id == "ch_test" }.count == 1)
    }

    @Test("The total is every balance converted home")
    func totalConvertsEverything() {
        let wallet = Wallet(store: nil)
        let expected = Currency.allCases.reduce(0) {
            $0 + FX.convert(wallet.balance(in: $1), to: .home).minorUnits
        }
        #expect(wallet.total == Money(minorUnits: expected, currency: .home))
    }

    @Test("A payment lowers the total by its converted amount, give or take the rounding")
    func totalDrops() {
        let wallet = Wallet(store: nil)
        let before = wallet.total.minorUnits
        wallet.record(receipt(), card: Card.samples[0])
        // Each balance is converted and rounded on its own, so the total can move by
        // one minor unit more or less than the payment converted alone. That is a real
        // property of a multi-currency total, not an error in it.
        let drop = before - wallet.total.minorUnits
        #expect(abs(drop - 331) <= 1)
    }
}

// MARK: - Persistence

@MainActor
@Suite("Persistence")
struct PersistenceTests {

    private func temporaryStore() -> WalletStore {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "wallet-\(UUID().uuidString).json")
        return WalletStore(url: url)
    }

    @Test("What was paid is still there after a relaunch")
    func roundTrip() {
        let store = temporaryStore()
        let receipt = Receipt(id: "ch_persisted", amount: Money(minorUnits: 1_250, currency: .sgd),
                              merchant: .sample, last4: "4821", completedAt: .now, wasReplay: true)

        let first = Wallet(store: store)
        first.record(receipt, card: Card.samples[0])
        first.toggleFreeze(Card.samples[1])

        let second = Wallet(store: store)
        #expect(second.transactions.first?.id == "ch_persisted")
        #expect(second.transactions.first?.receipt?.wasReplay == true)
        #expect(second.balance(in: .sgd) == first.balance(in: .sgd))
        #expect(second.isFrozen(Card.samples[1]))
    }

    @Test("A wallet with no file starts from the opening balances")
    func freshStart() {
        let wallet = Wallet(store: temporaryStore())
        #expect(wallet.balances == Wallet.openingBalances)
        #expect(wallet.transactions == Transaction.samples)
    }
}

// MARK: - Accent

@Suite("Accent")
struct AccentTests {

    @Test("A light accent gets dark text, a dark one gets white")
    func textFollowsTheColour() {
        #expect(Theme.prefersDarkText(on: 0xF5C542))      // saffron
        #expect(Theme.prefersDarkText(on: 0xB9AEF0))      // lavender
        #expect(!Theme.prefersDarkText(on: 0x2F3E75))     // navy
        #expect(!Theme.prefersDarkText(on: 0x5B2A86))     // violet
    }

    @Test("Overriding the accent leaves the rest of the theme as it was")
    func onlyTheAccentChanges() {
        let theme = Theme.graphite
        let tinted = theme.withAccent(0x3FB8A0)
        #expect(tinted.accent == Color(hex: 0x3FB8A0))
        #expect(tinted.canvas == theme.canvas)
        #expect(tinted.primary == theme.primary)
        #expect(tinted.isDark == theme.isDark)
    }

    @Test("Gift cards bring their own colours and say what they are")
    func giftCards() {
        let gifts = Card.samples.filter(\.isGift)
        #expect(gifts.count == 3)
        #expect(gifts.allSatisfy { $0.kindLabel == "Gift card" })
    }
}

// MARK: - Gift cards

@MainActor
@Suite("Gift cards")
struct GiftCardTests {

    private func receipt(_ id: String, _ minor: Int, _ currency: Currency = .sgd) -> Receipt {
        Receipt(id: id, amount: Money(minorUnits: minor, currency: currency),
                merchant: .sample, last4: "0876", completedAt: .now)
    }

    @Test("Paying with a gift card spends the gift, not the wallet")
    func giftSpendsItsOwnBalance() throws {
        let wallet = Wallet(store: nil)
        let winter = try #require(wallet.card("gift-winter"))
        let sgd = wallet.balance(in: .sgd)

        wallet.record(receipt("ch_flight", 48_600), card: winter)

        #expect(wallet.giftBalance(of: winter) == Money(minorUnits: 11_400, currency: .sgd))
        #expect(wallet.balance(in: .sgd) == sgd)
    }

    @Test("A gift card cannot cover more than is on it")
    func giftCannotOverspend() throws {
        let wallet = Wallet(store: nil)
        let weekend = try #require(wallet.card("gift-weekend"))     // SGD 80
        #expect(!wallet.canPay(Money(minorUnits: 48_600, currency: .sgd), with: weekend))
        #expect(wallet.canPay(Money(minorUnits: 1_250, currency: .sgd), with: weekend))
        // In another currency it is converted first: €18.40 is about SGD 26.67.
        #expect(wallet.canPay(Money(minorUnits: 1_840, currency: .eur), with: weekend))
    }

    @Test("A bought gift card joins the wallet with its amount, and survives a relaunch")
    func boughtGiftPersists() throws {
        let store = WalletStore(url: FileManager.default.temporaryDirectory
            .appending(path: "wallet-\(UUID().uuidString).json"))
        let first = Wallet(store: store)
        let count = first.cards.count
        let card = first.addGift(.dusk, amount: Money(minorUnits: 20_000, currency: .sgd))

        let second = Wallet(store: store)
        #expect(second.cards.count == count + 1)
        let restored = try #require(second.card(card.id))
        #expect(restored.art == .dusk)
        #expect(second.giftBalance(of: restored) == Money(minorUnits: 20_000, currency: .sgd))
    }

    @Test("A new gift card's number fails Luhn, like every sample")
    func giftNumbersAreNotReal() {
        for _ in 0..<50 {
            let n = Card.gift(.night).number
            let digits = n.compactMap(\.wholeNumberValue)
            let sum = digits.reversed().enumerated().reduce(0) { t, p in
                guard p.offset % 2 == 1 else { return t + p.element }
                let d = p.element * 2
                return t + (d > 9 ? d - 9 : d)
            }
            #expect(digits.count == 16)
            #expect(sum % 10 != 0, "\(n) passes Luhn")
        }
    }

    @Test("A wallet saved before gift cards existed opens with the samples")
    func olderFilesStillOpen() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "old-\(UUID().uuidString).json")
        let old = #"{"balances":["SGD",100],"frozen":[],"transactions":[]}"#
        try Data(old.utf8).write(to: url)
        let wallet = Wallet(store: WalletStore(url: url))
        #expect(wallet.cards == Card.samples)
        #expect(wallet.giftBalances == Wallet.openingGiftBalances)
    }
}
