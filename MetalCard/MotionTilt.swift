import SwiftUI
import Combine
import CoreMotion

/// Device tilt, normalised to roughly -1...1 on both axes.
/// On the Simulator there is no motion, so `WalletView` also feeds a drag gesture into `tilt`.
@MainActor
final class MotionTilt: ObservableObject {
    @Published var value: CGSize = .zero

    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let attitude = motion?.attitude else { return }
            let x = CGFloat(max(-1, min(1, attitude.roll / 0.7)))
            let y = CGFloat(max(-1, min(1, attitude.pitch / 0.7)))
            // Smooth it, otherwise the highlight jitters.
            self.value = CGSize(width: self.value.width * 0.85 + x * 0.15,
                                height: self.value.height * 0.85 + y * 0.15)
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}
