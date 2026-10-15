# gatewayd

The payment gateway MetalCard pays against. Go 1.27, standard library only.

```
go run ./cmd/gatewayd -addr :8080 -drop 1
```

`-drop` swallows that many answers *after* the charge has gone through. That is the
case the whole design exists for: the money has moved, the caller does not know it,
and the retry must not take it again.

## Endpoints

| | |
|---|---|
| `POST /v1/charges` | charges a card; the key travels in an `Idempotency-Key` header |
| `GET /v1/charges/{id}` | reads a charge back |
| `GET /healthz` | status, uptime, and how many times money has actually moved |

## What the key buys you

A key stands for one request, not for whatever request happens to carry it. The
gateway stores a fingerprint of the amount, currency, merchant and last four digits
beside the receipt:

| situation | answer |
|---|---|
| same key, same request | `200` with `Idempotent-Replayed: true` — the stored receipt |
| same key, different request | `422 key_reused` — replaying the wrong receipt would be worse than charging twice |
| same key, still in flight | `409 request_in_flight`, retriable |
| not enough money | `402` — a decline is an answer, recorded against the key so a retry gets the same one |

The claim and the lookup happen under one lock. Checking first and claiming
afterwards would let two requests that arrive together both find nothing and both
charge; `TestConcurrentDuplicatesChargeOnce` runs twenty goroutines at one key to
prove they do not.

Records live for 24 hours, the same window Stripe and Airwallex use.

```
go test -race ./...
```
