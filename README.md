# Metal Card

A fintech card that behaves like a physical one: brushed-metal sheen that follows the phone,
a holographic band, and ice that creeps in from the edges when you freeze the card.
SwiftUI for the layout, Metal shaders for everything that has to feel real.

## Run it

1. Xcode 15+, iOS 17+ (the `.colorEffect` shader API is iOS 17).
2. New project → App → SwiftUI → name it `MetalCard`.
3. Drop the files from `MetalCard/` into the target: `MetalCardApp.swift`, `WalletView.swift`,
   `CardView.swift`, `Card.swift`, `MotionTilt.swift`, `Shaders.metal`.
4. `Shaders.metal` must be in *Target Membership* and in *Build Phases → Compile Sources*.
5. Run on a device. The Simulator has no motion, so tilt is driven by dragging the card instead.

## What is where

| File | What it does |
|---|---|
| `Shaders.metal` | `sheen` — specular band + brushed grain + holographic tint, driven by tilt. `frost` — ice front growing inwards from the edges, with veins and sparkle. |
| `CardView.swift` | Card body, front and back, flip, number reveal, shader overlays. |
| `WalletView.swift` | Wallet stack, zoom into detail with `matchedGeometryEffect`, controls. |
| `MotionTilt.swift` | CoreMotion attitude → smoothed tilt vector. |

## Notes on the shaders

- SwiftUI passes **premultiplied** colors, so both shaders return `half4(rgb * alpha, alpha)`.
- `sheen` is composited with `.plusLighter` — it adds light, it never darkens the card.
- `frost` uses the distance to the nearest edge as the ice front, and fbm noise to break
  the front into crystals, so the freeze does not look like a rectangle sliding in.
- Time comes from `TimelineView(.animation)`, so the shaders keep moving without a timer.

## Numbers are fake

The PANs in `Card.samples` are made up and fail the Luhn check on purpose. Keep it that way.

## For the video

Record on a device, portrait, 15–20 seconds:
1. Wallet stack, tap a card — it flies out (2s).
2. Slowly tilt the phone — the highlight and the rainbow travel across the metal (4s).
3. Tap **Details** — the number resolves out of the blur, digits roll (3s).
4. Tap **Flip** — the back with CVV (2s).
5. Tap **Freeze** — ice crawls in from the edges (4s), then unfreeze (2s).

Export at 1080×1920. The freeze is the shot people stop scrolling for, so let it play out.
