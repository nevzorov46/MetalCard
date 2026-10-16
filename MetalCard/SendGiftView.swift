import SwiftUI

/// Someone to send a gift card to.
struct GiftRecipient: Identifiable, Hashable {
    let id: String
    let name: String
    let tint: Color

    var firstName: String { String(name.split(separator: " ").first ?? "") }
    var initials: String { name.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined() }

    static let contacts: [GiftRecipient] = [
        GiftRecipient(id: "anna",   name: "Anna Petrova", tint: Color(hex: 0x7FA8C4)),
        GiftRecipient(id: "mark",   name: "Mark Lee",     tint: Color(hex: 0x8CCB7E)),
        GiftRecipient(id: "sofia",  name: "Sofia Romano", tint: Color(hex: 0xE59DB3)),
        GiftRecipient(id: "daniel", name: "Daniel Kim",   tint: Color(hex: 0xF5C542))
    ]
}

/// A gift card for someone else: who it is for, a drawing, an amount and a line from you.
/// It is paid for with one of your cards through the same checkout as any purchase, and
/// then it is theirs — it leaves, it does not land in your wallet.
struct SendGiftView: View {
    @Environment(Wallet.self) private var wallet
    @Environment(\.theme) private var palette
    @Environment(MotionTilt.self) private var motion

    let funding: Card
    let gateway: any ChargeGateway
    let onDone: () -> Void

    @State private var recipient = GiftRecipient.contacts[0]
    @State private var art: CardArt = .confetti
    @State private var amount = 10_000
    @State private var message = ""
    @State private var checkout: Checkout?
    @State private var sent = false
    @FocusState private var writing: Bool

    private static let amounts = [5_000, 10_000, 20_000, 50_000]

    private var price: Money { Money(minorUnits: amount, currency: .sgd) }
    private var busy: Bool { checkout?.phase.isBusy ?? false }

    /// The card as they will see it.
    private var gift: Card {
        Card(id: "gift-for-\(recipient.id)", name: "For \(recipient.firstName)", number: "000000000000····",
             expiry: "", cvv: "", holder: recipient.name.uppercased(), style: .primary, art: art)
    }

    var body: some View {
        // Scrolls, with the button pinned underneath: when the keyboard is up there is not
        // room for everything, and the card should move out of the way rather than vanish.
        ScrollView {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(sent ? "Sent to \(recipient.firstName)" : "Send a gift card")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(palette.ink)
                    .contentTransition(.opacity)
                Text(sent ? "\(price.formatted) for \(recipient.name) to spend"
                          : "Paid with \(funding.name) ···· \(funding.last4)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.inkTertiary)
                    .contentTransition(.opacity)
            }
            .padding(.top, 26)

            if !sent {
                recipients.padding(.top, 20)
            }

            CardView(card: gift, tilt: motion.tilt)
                .frame(width: sent ? 230 : 250, height: (sent ? 230 : 250) / CardView.aspect)
                .rotationEffect(.degrees(sent ? -4 : 0))
                .padding(.top, sent ? 34 : 18)
                .id("\(recipient.id)-\(art.rawValue)")
                .transition(.opacity)

            if sent {
                if !message.isEmpty {
                    Text("“\(message)”")
                        .font(.system(size: 17, weight: .medium))
                        .italic()
                        .foregroundStyle(palette.ink)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                        .padding(.top, 26)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                Text("\(recipient.firstName) gets it by message, with your note.")
                    .font(.system(size: 14))
                    .foregroundStyle(palette.inkTertiary)
                    .padding(.top, 12)
            } else {
                picker.padding(.top, 20)
                amounts.padding(.top, 16)
                note.padding(.top, 16).padding(.horizontal, 24).id("note")
            }
        }
        .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
        VStack(spacing: 0) {
            Text(status)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.inkTertiary)
                .frame(height: 18)
                .padding(.bottom, 8)

            button
                .padding(.horizontal, 24)
                .padding(.bottom, 26)
        }
        .background(palette.canvas)
        }
        .background(palette.canvas)
        .animation(.smooth(duration: 0.35), value: art)
        .animation(.smooth(duration: 0.35), value: recipient)
        .animation(.smooth(duration: 0.5), value: sent)
        .sensoryFeedback(.success, trigger: sent)
        .onChange(of: checkout?.phase) { _, phase in
            guard case .approved(let receipt) = phase, !sent else { return }
            // A payment from your card; the gift card itself goes to them.
            wallet.record(receipt, card: funding)
            writing = false
            sent = true
        }
    }

    // MARK: Pieces

    private var recipients: some View {
        HStack(spacing: 18) {
            ForEach(GiftRecipient.contacts) { person in
                let selected = person == recipient
                Button { recipient = person } label: {
                    VStack(spacing: 6) {
                        Text(person.initials)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(hex: 0x14131A))
                            .frame(width: 50, height: 50)
                            .background(person.tint, in: Circle())
                            .padding(3)
                            .overlay(Circle().strokeBorder(selected ? palette.ink : .clear, lineWidth: 2))
                        Text(person.firstName)
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? palette.ink : palette.inkTertiary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
        }
    }

    private var picker: some View {
        HStack(spacing: 14) {
            ForEach(CardArt.allCases, id: \.self) { option in
                Button { art = option } label: {
                    ZStack {
                        option.base
                        CardArtView(art: option)
                    }
                    .frame(width: 78, height: 49)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(3)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(art == option ? palette.ink : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.displayName)
                .disabled(busy)
            }
        }
    }

    private var amounts: some View {
        HStack(spacing: 10) {
            ForEach(Self.amounts, id: \.self) { value in
                let selected = value == amount
                Button { amount = value } label: {
                    // Whole amounts, so four fit on a line: "SGD 50", not "SGD 50.00".
                    Text("SGD \(value / 100)")
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(selected ? palette.canvas : palette.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(selected ? palette.ink : palette.surface, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
        }
    }

    private var note: some View {
        TextField("A line for \(recipient.firstName)", text: $message, axis: .vertical)
            .lineLimit(1...2)
            .focused($writing)
            .submitLabel(.done)
            .font(.system(size: 15))
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .disabled(busy)
    }

    private var button: some View {
        Button {
            if sent { onDone(); return }
            writing = false
            if checkout == nil || checkout?.amount != price || checkout?.merchant.name != merchant.name {
                checkout = Checkout(amount: price, merchant: merchant, client: PaymentClient(gateway: gateway))
            }
            checkout?.pay(card: funding, isFrozen: wallet.isFrozen(funding))
        } label: {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(palette.onAccent) }
                Text(title).font(.system(size: 17, weight: .bold))
            }
            .foregroundStyle(palette.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(palette.accent, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    /// What the purchase is called in your history.
    private var merchant: Merchant {
        Merchant(name: "Gift to \(recipient.name)", category: "\(art.displayName) gift card", symbol: "gift.fill")
    }

    private var title: String {
        if sent { return "Done" }
        switch checkout?.phase {
        case .confirming: return "Confirm with Face ID"
        case .charging:   return "Sending"
        case .failed:     return "Try again"
        default:          return "Send \(price.formatted) to \(recipient.firstName)"
        }
    }

    private var status: String {
        switch checkout?.phase {
        case .charging(let n) where n > 1: "No answer — retrying with the same key"
        case .failed(let error):           error.message
        default:                           ""
        }
    }
}
