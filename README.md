# Metal Card

A wallet you can pay from, wearing a card that behaves like a physical one: brushed-metal
sheen that follows the phone, a holographic band, and ice that creeps across the card when
you freeze it. SwiftUI for the layout, Metal shaders for everything that has to feel real,
and a payment path built the way money actually has to be moved.

## Paying

Tap **Pay**, confirm with Face ID, and the charge goes out. What happens underneath is the
part worth reading:

- **Money is counted in minor units.** Cents, not euros, and never a binary float. The
  exponent comes from the currency, so yen is formatted without decimals and the code does
  not assume everyone has two.
- **Every payment carries an idempotency key**, made once per intent to pay. The key is
  what lets the gateway tell a retry apart from a second purchase.
- **A lost response is retried; a decline is not.** A decline is an answer, and asking the
  same question again would be both pointless and rude to the customer.
- **The gateway claims the key before its first `await`.** An actor protects state at an
  instant, not across a suspension — without the claim, two requests arriving together both
  find an empty table and both take the money. There is a test that races them.
- **A frozen card is stopped on the device.** It never reaches the network, which is the
  whole point of freezing it. The ice is the feature, not a decoration over one.
- **The card number is held back** until the holder asks for it, and the sample PANs fail
  the Luhn check on purpose — there is a test that checks they still do.

Seventeen tests cover the money arithmetic, the retry and replay paths, the race, and the
flow's state machine. `.github/workflows/ci.yml` builds and runs them on every push.

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
| `Payment.swift` | `Money` in minor units, `Currency` with its own exponent, the idempotency key, the errors. |
| `PaymentGateway.swift` | The gateway as an actor: the record of charged keys, the dropped response, the retrying client. |
| `Checkout.swift` | One checkout from sheet to receipt, and who is allowed to confirm it. |
| `CheckoutView.swift` | The pay sheet; one button that changes its mind as the payment moves. |
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
