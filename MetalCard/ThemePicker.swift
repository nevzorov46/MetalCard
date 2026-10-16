import SwiftUI

/// Themes and the accent. Tapping either restyles the app behind the sheet straight away,
/// so they can be compared without closing it.
struct ThemePicker: View {
    @Environment(Appearance.self) private var appearance
    @Environment(\.theme) private var palette

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    private let accentColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Theme")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(palette.ink)

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Theme.all) { theme in
                        Button {
                            withAnimation(.easeInOut(duration: 0.45)) { appearance.themeID = theme.id }
                        } label: {
                            swatch(theme, selected: theme.id == appearance.themeID)
                        }
                        .buttonStyle(.plain)
                    }
                }

                accent.padding(.top, 10)
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)
            .padding(.bottom, 30)
        }
        .scrollBounceBehavior(.basedOnSize)
        .sensoryFeedback(.selection, trigger: appearance.themeID)
        .sensoryFeedback(.selection, trigger: appearance.accentRGB)
    }

    // MARK: Accent

    private var accent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Accent")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(palette.ink)
                Spacer()
                if appearance.accentRGB != nil {
                    Button("Use theme's") {
                        withAnimation(.easeInOut(duration: 0.3)) { appearance.accentRGB = nil }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .tint(palette.inkSecondary)
                }
            }

            LazyVGrid(columns: accentColumns, spacing: 12) {
                ForEach(Theme.accentSwatches, id: \.self) { rgb in
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) { appearance.accentRGB = rgb }
                    } label: {
                        dot(Color(hex: rgb), selected: appearance.accentRGB == rgb)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(format: "Accent #%06X", rgb))
                }

                // Every other colour.
                ColorPicker("Any colour", selection: anyColour, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 40, height: 40)
                    .overlay {
                        if let rgb = appearance.accentRGB, !Theme.accentSwatches.contains(rgb) {
                            Circle().strokeBorder(palette.ink, lineWidth: 2).frame(width: 46, height: 46)
                        }
                    }
                    .frame(maxWidth: .infinity)
            }

            Text("The last swatch opens every colour. Text on the accent switches between light and dark by itself.")
                .font(.system(size: 13))
                .foregroundStyle(palette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var anyColour: Binding<Color> {
        Binding(get: { palette.accent },
                set: { appearance.accentRGB = $0.rgb24 })
    }

    private func dot(_ colour: Color, selected: Bool) -> some View {
        Circle()
            .fill(colour)
            .frame(width: 40, height: 40)
            .overlay(Circle().strokeBorder(palette.ink.opacity(0.10), lineWidth: 1))
            .padding(3)
            .overlay(Circle().strokeBorder(selected ? palette.ink : .clear, lineWidth: 2))
            .frame(maxWidth: .infinity)
            .contentShape(Circle())
    }

    // MARK: Themes

    /// A tiny wallet in the theme's own colours: its canvas, the metal card behind,
    /// the primary card in front.
    private func swatch(_ theme: Theme, selected: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.metal.base)
                    .frame(width: 50, height: 32)
                    .offset(x: 8, y: -7)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.primary.base)
                    .frame(width: 50, height: 32)
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
                    .offset(x: -6, y: 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .background(theme.canvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? palette.ink : palette.ink.opacity(0.08),
                                  lineWidth: selected ? 2 : 1)
            )

            Text(theme.name)
                .font(.system(size: 13, weight: selected ? .bold : .semibold))
                .foregroundStyle(selected ? palette.ink : palette.inkTertiary)
        }
    }
}
