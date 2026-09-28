#if DEBUG
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// A soft circle under every finger, for screen recordings. `simctl io recordVideo` captures the
/// device screen at full resolution, but it shows neither the mouse nor the taps.
///
/// Off by default. Turn it on for one launch with the argument `-showTouches YES`, or keep it on
/// with `xcrun simctl spawn booted defaults write com.nevzorov.MetalCard showTouches -bool YES`.
enum TouchIndicators {
    private static var overlay: UIWindow?

    static func installIfRequested() {
        guard overlay == nil,
              UserDefaults.standard.bool(forKey: "showTouches"),
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let appWindow = scene.windows.first else { return }

        // A window of its own, above everything, sheets included. It takes no touches,
        // so they fall through to the app underneath.
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = false
        window.isHidden = false
        overlay = window

        appWindow.addGestureRecognizer(TouchTracker(canvas: window))
    }
}

/// Sees every touch in the app window without ever taking part in gesture recognition:
/// it never begins, never prevents anything and can't be prevented.
private final class TouchTracker: UIGestureRecognizer {
    private let canvas: UIView
    private var dots: [ObjectIdentifier: UIView] = [:]

    init(canvas: UIView) {
        self.canvas = canvas
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            let dot = Self.makeDot()
            dot.center = touch.location(in: canvas)
            dot.alpha = 0
            dot.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
            canvas.addSubview(dot)
            dots[ObjectIdentifier(touch)] = dot
            UIView.animate(withDuration: 0.12) {
                dot.alpha = 1
                dot.transform = .identity
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            dots[ObjectIdentifier(touch)]?.center = touch.location(in: canvas)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { lift(touches, in: event) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { lift(touches, in: event) }

    private func lift(_ touches: Set<UITouch>, in event: UIEvent) {
        for touch in touches {
            guard let dot = dots.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            UIView.animate(withDuration: 0.25) {
                dot.alpha = 0
                dot.transform = CGAffineTransform(scaleX: 1.4, y: 1.4)
            } completion: { _ in
                dot.removeFromSuperview()
            }
        }
        // Failing once every finger is up resets the tracker for the next touch.
        let allUp = event.allTouches?.allSatisfy { $0.phase == .ended || $0.phase == .cancelled } ?? true
        if allUp {
            state = .failed
        }
    }

    private static func makeDot() -> UIView {
        let size: CGFloat = 44
        let dot = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        dot.isUserInteractionEnabled = false
        dot.layer.cornerRadius = size / 2
        dot.backgroundColor = UIColor.black.withAlphaComponent(0.16)
        dot.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        dot.layer.borderWidth = 2
        dot.layer.shadowColor = UIColor.black.cgColor
        dot.layer.shadowOpacity = 0.2
        dot.layer.shadowRadius = 6
        dot.layer.shadowOffset = .zero
        return dot
    }
}
#endif
