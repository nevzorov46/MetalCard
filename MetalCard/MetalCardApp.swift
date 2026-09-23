import SwiftUI

@main
struct MetalCardApp: App {
    var body: some Scene {
        WindowGroup {
            WalletView()
                .preferredColorScheme(.dark)
                .statusBarHidden()
        }
    }
}
