import SwiftUI

/// A card in the wallet. The numbers are made up and fail the Luhn check on purpose.
struct Card: Identifiable, Hashable {
    /// Which of the theme's colourways the card wears. The colours themselves live in
    /// `Theme`, so a new theme recolours every card without touching this list.
    enum Style: Hashable {
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

    var finish: Finish { style == .metal ? .metal : .matte }
    var last4: String { String(number.suffix(4)) }

    var groupedNumber: String {
        stride(from: 0, to: number.count, by: 4).map { offset in
            let start = number.index(number.startIndex, offsetBy: offset)
            let end = number.index(start, offsetBy: 4, limitedBy: number.endIndex) ?? number.endIndex
            return String(number[start..<end])
        }.joined(separator: " ")
    }

    var kindLabel: String { isVirtual ? "Virtual card" : (finish == .metal ? "Metal card" : "Debit card") }

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
             style: .tertiary, isVirtual: true)
    ]
}
