import SwiftUI

/// One card, up close. The card itself is drawn by `HomeView`'s hero layer and flies into
/// the empty slot at the top of this screen; everything else fades in underneath it.
struct CardDetailView: View {
    let card: Card
    let hero: Namespace.ID
    @Binding var showsDetails: Bool
    var pull: CGFloat                   // 0...1, how far the card is being pulled down
    var onClose: () -> Void

    @Environment(Wallet.self) private var wallet
    @Environment(\.theme) private var palette
    @State private var appeared = false

    private var isFrozen: Bool { wallet.isFrozen(card) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            // The hero card lands here. It stays put while the list below scrolls.
            Color.clear
                .aspectRatio(CardView.aspect, contentMode: .fit)
                .matchedGeometryEffect(id: HomeView.slot(card.id), in: hero)
                .padding(.horizontal, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(card.name) card")
                            .font(.display(36))
                            .foregroundStyle(palette.ink)
                        Text("\(card.kindLabel) · •• \(card.last4)")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(palette.inkTertiary)
                    }
                    .padding(.bottom, 24)

                    actions.padding(.bottom, 24)

                    if isFrozen {
                        frozenBanner
                            .padding(.bottom, 24)
                            // Arriving, it waits a beat for the rows below to make room; leaving,
                            // it fades before they slide up. Either way it never sits on top of them.
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
                                    .animation(.snappy.delay(0.1)),
                                removal: .opacity.animation(.easeOut(duration: 0.15))))
                    }

                    settings
                }
                .padding(.horizontal, 20)
                .padding(.top, 26)
                .padding(.bottom, 40)
                .opacity(appeared ? 1 - pull : 0)
                .offset(y: appeared ? 0 : 36)
            }
            .scrollIndicators(.hidden)
        }
        .background(palette.canvas)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86).delay(0.12)) { appeared = true }
        }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.9), trigger: isFrozen)
        .sensoryFeedback(.selection, trigger: showsDetails)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .frame(width: 44, height: 44)
                    .background(palette.surface, in: Circle())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .opacity(appeared ? 1 - pull : 0)
    }

    // MARK: Actions

    private var actions: some View {
        HStack(alignment: .top, spacing: 0) {
            action(isFrozen ? "Unfreeze" : "Freeze", symbol: "snowflake",
                   active: isFrozen, fill: palette.iceSurface, ink: palette.iceInk) {
                // The interface answers at once; only the ice itself takes its time,
                // on the card's own animation (see `HomeView.heroCard`).
                withAnimation(.snappy) { wallet.toggleFreeze(card) }
            }
            action(showsDetails ? "Hide details" : "Show details",
                   symbol: showsDetails ? "eye.slash.fill" : "eye.fill",
                   active: showsDetails, fill: palette.accentSoft, ink: palette.accent) {
                showsDetails.toggle()
            }
            action("Limits", symbol: "gauge.with.dots.needle.50percent",
                   active: false, fill: palette.surface, ink: palette.ink) {}
            action("Settings", symbol: "gearshape.fill",
                   active: false, fill: palette.surface, ink: palette.ink) {}
        }
    }

    private func action(_ title: String, symbol: String, active: Bool,
                        fill: Color, ink: Color, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .symbolEffect(.bounce, value: active)
                    .foregroundStyle(active ? ink : palette.ink)
                    .frame(width: 58, height: 58)
                    .background(active ? fill : palette.surface, in: Circle())
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.interpolate)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var frozenBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "snowflake")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(palette.iceInk)
            VStack(alignment: .leading, spacing: 2) {
                Text("Card frozen")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.ink)
                Text("Payments are paused. Unfreeze any time.")
                    .font(.system(size: 14))
                    .foregroundStyle(palette.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(palette.iceSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Settings

    private var settings: some View {
        VStack(spacing: 18) {
            settingsRow("gauge.with.dots.needle.33percent", "Spending limit", "€1,240 of €2,000 left this month")
            settingsRow("lock.fill", "Change PIN", nil)
            settingsRow("arrow.triangle.2.circlepath", "Replace card", "Lost, stolen or damaged")
            settingsRow("xmark.octagon.fill", "Cancel card", nil)
        }
    }

    private func settingsRow(_ symbol: String, _ title: String, _ detail: String?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.ink)
                .frame(width: 46, height: 46)
                .background(palette.surface, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.ink)
                if let detail {
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundStyle(palette.inkTertiary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.inkTertiary)
        }
    }
}
