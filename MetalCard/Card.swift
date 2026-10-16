import SwiftUI

/// A card in the wallet. The numbers are made up and fail the Luhn check on purpose.
struct Card: Identifiable, Hashable, Codable {
    /// Which of the theme's colourways the card wears. The colours themselves live in
    /// `Theme`, so a new theme recolours every card without touching this list.
    enum Style: Hashable, Codable {
        case primary, metal, secondary, tertiary
    }

    enum Finish: Hashable {
        case matte
        case metal
    }

    let id: String
    var name: String
    var number: String          // 16 digits, no spaces
    var expiry: String
    var cvv: String
    var holder: String
    var style: Style
    var isVirtual = false
    /// A gift card's illustration. It brings its own colours, so the theme leaves it alone.
    var art: CardArt? = nil
    /// Who gave it, for a gift card someone sent.
    var from: String? = nil

    var finish: Finish { style == .metal ? .metal : .matte }
    var last4: String { String(number.suffix(4)) }

    var groupedNumber: String {
        stride(from: 0, to: number.count, by: 4).map { offset in
            let start = number.index(number.startIndex, offsetBy: offset)
            let end = number.index(start, offsetBy: 4, limitedBy: number.endIndex) ?? number.endIndex
            return String(number[start..<end])
        }.joined(separator: " ")
    }

    var isGift: Bool { art != nil }

    var kindLabel: String {
        if isGift { return "Gift card" }
        return isVirtual ? "Virtual card" : (finish == .metal ? "Metal card" : "Debit card")
    }

    static let samples: [Card] = [
        Card(id: "everyday", name: "Everyday",
             number: "4000821093354821", expiry: "07/29", cvv: "418", holder: "VALERY NEVZOROV",
             style: .primary),
        Card(id: "metal", name: "Metal",
             number: "4012340056789010", expiry: "03/30", cvv: "902", holder: "VALERY NEVZOROV",
             style: .metal),
        Card(id: "travel", name: "Travel",
             number: "4096771830024418", expiry: "11/28", cvv: "233", holder: "VALERY NEVZOROV",
             style: .secondary),
        Card(id: "online", name: "Online",
             number: "4111220033445566", expiry: "05/27", cvv: "617", holder: "VALERY NEVZOROV",
             style: .tertiary, isVirtual: true),
        Card(id: "gift-birthday", name: "Birthday gift",
             number: "4532810077461203", expiry: "12/27", cvv: "305", holder: "VALERY NEVZOROV",
             style: .primary, art: .confetti, from: "Mark Lee"),
        Card(id: "gift-winter", name: "Winter gift",
             number: "4024007193520876", expiry: "02/28", cvv: "771", holder: "VALERY NEVZOROV",
             style: .primary, art: .night, from: "Anna Petrova"),
        Card(id: "gift-weekend", name: "Weekend gift",
             number: "4916338512064459", expiry: "09/28", cvv: "148", holder: "VALERY NEVZOROV",
             style: .primary, art: .dusk, from: "Sofia Romano")
    ]
}
