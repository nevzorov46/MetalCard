import SwiftUI

/// A card in the wallet. The numbers are made up and fail the Luhn check on purpose.
struct Card: Identifiable, Hashable {
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
    var base: Color
    var ink: Color
    var finish: Finish = .matte
    var isVirtual = false

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
             base: Palette.accent, ink: Palette.onAccent),
        Card(id: "metal", name: "Metal",
             number: "4012340056789010", expiry: "03/30", cvv: "902", holder: "VALERY NEVZOROV",
             base: Color(hex: 0x1E1830), ink: Color(hex: 0xCFC4FF), finish: .metal),
        Card(id: "travel", name: "Travel",
             number: "4096771830024418", expiry: "11/28", cvv: "233", holder: "VALERY NEVZOROV",
             base: Color(hex: 0xFFCFB0), ink: Color(hex: 0x3F1C0B)),
        Card(id: "online", name: "Online",
             number: "4111220033445566", expiry: "05/27", cvv: "617", holder: "VALERY NEVZOROV",
             base: Color(hex: 0xFFE7A0), ink: Color(hex: 0x2E2200), isVirtual: true)
    ]
}
