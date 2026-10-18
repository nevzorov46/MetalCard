# One key per month

A payments wallet: SwiftUI on iOS, a Go gateway behind it.

**[Watch it run](docs/one-key-per-month.mp4)** — 36 seconds, recorded on a phone: subscribe,
bill a month, lose the answer, retry, and the charge count stays at one.

## The problem

The phone asks the server to charge $4.99. The server charges the card, writes the
receipt and answers "done". The answer gets lost.

Nothing comes back, and the app cannot tell two things apart:

- the request never arrived, no money moved
- the money moved, only the answer was lost

Stay quiet, and the customer paid without ever seeing a receipt. Ask again, and you can
charge them twice.

## The answer

Every charge carries an idempotency key — one key for one purchase, not one per attempt.
The gateway keeps a table of key → receipt:

- **new key** — charge, store the receipt, answer
- **known key** — change nothing, return the same receipt

A retry is then safe. The phone can ask ten times; the money moves once.

Subscriptions go further. The merchant bills every month with no customer present, so the
key is the subscription and the month — `sub-<id>:2026-11`. The billing job can crash,
redeploy and run the same month again; that month is still charged once.

## Three things that matter

**The key is claimed before the first `await`.** An actor protects state at an instant,
not across a suspension. Without the claim, two requests arriving together both find an
empty table and both take the money. `PaymentTests` races them on purpose.

**A lost response is retried; a decline is not.** A decline is an answer.

**Money is counted in minor units**, with the exponent taken from the currency, so yen is
formatted without decimals and nothing assumes everyone has two.

## Where to look

| File | What it holds |
|---|---|
| `MetalCard/Payment.swift` | `Money`, `Currency`, the idempotency key, the errors |
| `MetalCard/PaymentGateway.swift` | the gateway as an actor, the record of charged keys, the retrying client |
| `MetalCard/Subscriptions.swift` | the per-month key and the merchant's billing run |
| `MetalCard/Checkout.swift` | one checkout from sheet to receipt |
| `server/internal/gateway` | the same rules in Go, over HTTP |

## Running it

Open `MetalCard.xcodeproj` and run. The app charges against an in-process gateway that
drops the first answer on purpose — that is what the video shows.

To pay against the Go service instead:

```bash
cd server && go run ./cmd/gatewayd
```

then launch the app with `-remote http://localhost:8080`.

## Tests

47 tests cover the money arithmetic, the retry and replay paths, the race, the
subscription keys and the wallet's own state. `.github/workflows/ci.yml` builds and runs
them on every push.

```bash
xcodebuild -scheme MetalCard -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
cd server && go test ./...
```
