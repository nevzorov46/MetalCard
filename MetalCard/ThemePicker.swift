import SwiftUI

/// A sheet of theme swatches. Tapping one restyles the app behind the sheet straight away,
/// so themes can be compared without closing it.
struct ThemePicker: View {
    @Environment(Appearance.self) private var appearance
    @Environment(\.theme) private var palette

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
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
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .sensoryFeedback(.selection, trigger: appearance.themeID)
    }

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
