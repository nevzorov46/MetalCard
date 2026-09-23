import SwiftUI

/// Shared state: the cards and which of them are frozen.
/// Freezing lives here, not in the detail screen, so a frozen card stays frosted
/// in the carousel after you zoom back out.
@Observable
final class Wallet {
    var cards = Card.samples
    var frozen: Set<Card.ID> = []
    let transactions = Transaction.samples

    func card(_ id: Card.ID) -> Card? { cards.first { $0.id == id } }
    func isFrozen(_ card: Card) -> Bool { frozen.contains(card.id) }

    func toggleFreeze(_ card: Card) {
        if frozen.contains(card.id) { frozen.remove(card.id) } else { frozen.insert(card.id) }
    }
}

struct Transaction: Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String
    var amount: String
    var symbol: String
    var incoming = false

    static let samples: [Transaction] = [
        Transaction(title: "Tamp & Grind", subtitle: "Today · Everyday", amount: "−€4.80", symbol: "cup.and.saucer.fill"),
        Transaction(title: "Anna Petrova", subtitle: "Today · Transfer", amount: "+€120.00", symbol: "arrow.down.left", incoming: true),
        Transaction(title: "Metro Taxi", subtitle: "Yesterday · Travel", amount: "−€18.40", symbol: "car.fill"),
        Transaction(title: "Green Basket", subtitle: "Yesterday · Everyday", amount: "−€36.15", symbol: "basket.fill"),
        Transaction(title: "Lumen Streaming", subtitle: "Mon · Online", amount: "−€9.99", symbol: "play.rectangle.fill")
    ]
}
