import SwiftUI

@main
struct MetalCardApp: App {
    @State private var wallet = Wallet()
    @State private var motion = MotionTilt()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(wallet)
                .environment(motion)
                .preferredColorScheme(.light)
                .onAppear { motion.start() }
                .task { await Self.warmUpShaders() }
        }
    }

    /// Compile the shaders up front. Otherwise Metal builds each pipeline the first time
    /// it is drawn, and the frost would skip its first half-second while that happens.
    private static func warmUpShaders() async {
        try? await ShaderLibrary.frost(.float2(CGSize.zero), .float(0), .float(0), .float2(CGSize.zero))
            .compile(as: .layerEffect)
        try? await ShaderLibrary.sheen(.float2(CGSize.zero), .float2(CGSize.zero), .float(0))
            .compile(as: .colorEffect)
        try? await ShaderLibrary.grain(.float(0), .float(0))
            .compile(as: .colorEffect)
    }
}
