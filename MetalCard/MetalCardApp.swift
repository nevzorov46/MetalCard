import SwiftUI

@main
struct MetalCardApp: App {
    @State private var wallet = Wallet()
    @State private var motion = MotionTilt()
    @State private var appearance = Appearance()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(wallet)
                .environment(motion)
                .environment(appearance)
                .onAppear {
                    motion.start()
                    #if DEBUG
                    TouchIndicators.installIfRequested()
                    #endif
                }
                .task { await Self.warmUpShaders() }
        }
    }

    /// Compile the shaders up front. Otherwise Metal builds each pipeline the first time
    /// it is drawn, and the frost would skip its first half-second while that happens.
    private static func warmUpShaders() async {
        try? await ShaderLibrary.frost(.float2(CGSize.zero), .float(0), .float(0), .float2(CGSize.zero))
            .compile(as: .layerEffect)
        try? await ShaderLibrary.holo(.float2(CGSize.zero), .float2(CGSize.zero))
            .compile(as: .colorEffect)
    }
}

/// Puts the chosen theme into the environment. A view rather than the scene, so that
/// reading `appearance` is tracked and a new theme re-renders everything below it.
private struct RootView: View {
    @Environment(Appearance.self) private var appearance

    var body: some View {
        let theme = appearance.theme
        HomeView()
            .environment(\.theme, theme)
            .preferredColorScheme(theme.isDark ? .dark : .light)
            .tint(theme.accent)
    }
}
