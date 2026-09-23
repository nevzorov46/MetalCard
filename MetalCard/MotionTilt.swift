import SwiftUI
import CoreMotion

/// Device tilt, roughly -1...1 on both axes, measured from how the phone was held
/// when tracking started. The Simulator has no motion, so the detail screen
/// lets you drag the card instead.
@Observable
final class MotionTilt {
    private(set) var tilt: CGSize = .zero

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var reference: CMAttitude?

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let attitude = motion?.attitude else { return }
            MainActor.assumeIsolated { self?.update(with: attitude) }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        reference = nil
    }

    private func update(with attitude: CMAttitude) {
        if reference == nil { reference = attitude.copy() as? CMAttitude }
        if let reference { attitude.multiply(byInverseOf: reference) }

        let x = max(-1, min(1, attitude.roll / 0.6))
        let y = max(-1, min(1, attitude.pitch / 0.6))
        // Low-pass filter, otherwise the highlight jitters.
        tilt = CGSize(width: tilt.width * 0.85 + x * 0.15,
                      height: tilt.height * 0.85 + y * 0.15)
    }
}
