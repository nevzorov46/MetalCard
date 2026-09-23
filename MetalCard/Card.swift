import SwiftUI

/// A card in the wallet. Numbers are fake on purpose — never ship real PANs in a demo.
struct Card: Identifiable, Equatable {
    let id = UUID()
    var label: String
    var holder: String
    var number: String          // 16 digits, no spaces
    var expiry: String
    var cvv: String
    var top: Color
    var bottom: Color

    var maskedNumber: String { "•••• •••• •••• " + String(number.suffix(4)) }

    var groupedNumber: String {
        stride(from: 0, to: number.count, by: 4).map { offset -> String in
            let start = number.index(number.startIndex, offsetBy: offset)
            let end = number.index(start, offsetBy: 4, limitedBy: number.endIndex) ?? number.endIndex
            return String(number[start..<end])
        }.joined(separator: " ")
    }

    static let samples: [Card] = [
        Card(label: "Metal",
             holder: "VALERY NEVZOROV",
             number: "4012340056789010",
             expiry: "07/29",
             cvv: "418",
             top: Color(red: 0.11, green: 0.13, blue: 0.18),
             bottom: Color(red: 0.04, green: 0.05, blue: 0.08)),
        Card(label: "Travel",
             holder: "VALERY NEVZOROV",
             number: "5299006612340077",
             expiry: "03/28",
             cvv: "902",
             top: Color(red: 0.16, green: 0.21, blue: 0.34),
             bottom: Color(red: 0.06, green: 0.08, blue: 0.16)),
        Card(label: "Savings",
             holder: "VALERY NEVZOROV",
             number: "4111220033445566",
             expiry: "11/30",
             cvv: "233",
             top: Color(red: 0.22, green: 0.17, blue: 0.13),
             bottom: Color(red: 0.08, green: 0.06, blue: 0.05))
    ]
}
