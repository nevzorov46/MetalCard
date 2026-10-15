// Package gateway is the part that moves the money.
//
// The case it exists for is not a declined payment. It is a successful one whose
// response is lost on the way back: the money has moved, the caller does not know
// it, and the retry that follows must not take it again. Everything here — the
// idempotency record, the claim, the fingerprint — is built around that one case.
package gateway

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"sync"
	"sync/atomic"
	"time"
)

var (
	// ErrDeclined is an answer, not a failure. The caller must not retry it.
	ErrDeclined = errors.New("declined")
	// ErrInFlight means the same key is already being charged. The caller may
	// retry once the first one has settled.
	ErrInFlight = errors.New("key already in flight")
	// ErrKeyReused means the key has been seen with a different request. Replaying
	// the stored answer would be wrong, and charging would double-spend the key.
	ErrKeyReused = errors.New("key reused with a different request")
)

// How long a settled key is remembered. Stripe and Airwallex both use 24 hours.
const RecordTTL = 24 * time.Hour

type Money struct {
	MinorUnits int64  `json:"minor_units"`
	Currency   string `json:"currency"`
}

type Request struct {
	Key      string
	Amount   Money
	Merchant string
	Last4    string
}

// fingerprint is what makes a key belong to one request rather than to any
// request that happens to carry it.
func (r Request) fingerprint() string {
	return fmt.Sprintf("%d|%s|%s|%s", r.Amount.MinorUnits, r.Amount.Currency, r.Merchant, r.Last4)
}

type Charge struct {
	ID          string    `json:"id"`
	Amount      Money     `json:"amount"`
	Merchant    string    `json:"merchant"`
	Last4       string    `json:"last4"`
	Status      string    `json:"status"`
	Reason      string    `json:"reason,omitempty"`
	CompletedAt time.Time `json:"completed_at"`
}

type record struct {
	fingerprint string
	charge      Charge
	declined    bool
	storedAt    time.Time
}

type Gateway struct {
	mu       sync.Mutex
	settled  map[string]record
	inFlight map[string]struct{}
	balances map[string]int64

	charges atomic.Int64
	now     func() time.Time
}

func New() *Gateway {
	return &Gateway{
		settled:  make(map[string]record),
		inFlight: make(map[string]struct{}),
		balances: map[string]int64{
			"EUR": 1_248_020,
			"USD": 34_215,
			"SGD": 189_040,
			"JPY": 86_400,
		},
		now: time.Now,
	}
}

// Charges counts the times money actually moved. After any storm of retries on
// one key it must still be 1, which is what the tests assert.
func (g *Gateway) Charges() int64 { return g.charges.Load() }

// Authorize charges the card, or replays what this key produced before.
// The second return value reports a replay.
func (g *Gateway) Authorize(req Request) (Charge, bool, error) {
	if err := g.claim(req); err != nil {
		var replay Charge
		var replayed bool
		if errors.Is(err, errSettled) {
			replay, replayed, err = g.replay(req)
			return replay, replayed, err
		}
		return Charge{}, false, err
	}
	defer g.release(req.Key)

	// The work. In a real gateway this is the call to the card network, and it is
	// the only part that takes any time.
	balance := g.balance(req.Amount.Currency)
	if req.Amount.MinorUnits > balance {
		charge := Charge{
			ID: newID(), Amount: req.Amount, Merchant: req.Merchant, Last4: req.Last4,
			Status: "declined", Reason: "insufficient funds", CompletedAt: g.now(),
		}
		// A decline is recorded against the key too, so a retry gets the same
		// answer instead of a second look at the balance.
		g.settle(req, record{fingerprint: req.fingerprint(), charge: charge, declined: true, storedAt: g.now()})
		return charge, false, fmt.Errorf("%w: insufficient funds", ErrDeclined)
	}

	// Past this line the money has moved, whatever happens next.
	g.charges.Add(1)
	g.debit(req.Amount)
	charge := Charge{
		ID: newID(), Amount: req.Amount, Merchant: req.Merchant, Last4: req.Last4,
		Status: "succeeded", CompletedAt: g.now(),
	}
	g.settle(req, record{fingerprint: req.fingerprint(), charge: charge, storedAt: g.now()})
	return charge, false, nil
}

// Lookup returns a charge by its id.
func (g *Gateway) Lookup(id string) (Charge, bool) {
	g.mu.Lock()
	defer g.mu.Unlock()
	for _, rec := range g.settled {
		if rec.charge.ID == id {
			return rec.charge, true
		}
	}
	return Charge{}, false
}

var errSettled = errors.New("already settled")

// claim takes the key for the duration of the charge. It holds the lock across
// both the lookup and the insert: checking first and claiming afterwards would
// let two requests that arrive together both find nothing and both charge.
func (g *Gateway) claim(req Request) error {
	g.mu.Lock()
	defer g.mu.Unlock()

	g.sweepLocked()

	if rec, ok := g.settled[req.Key]; ok {
		if rec.fingerprint != req.fingerprint() {
			return ErrKeyReused
		}
		return errSettled
	}
	if _, ok := g.inFlight[req.Key]; ok {
		return ErrInFlight
	}
	g.inFlight[req.Key] = struct{}{}
	return nil
}

func (g *Gateway) release(key string) {
	g.mu.Lock()
	delete(g.inFlight, key)
	g.mu.Unlock()
}

func (g *Gateway) replay(req Request) (Charge, bool, error) {
	g.mu.Lock()
	rec, ok := g.settled[req.Key]
	g.mu.Unlock()
	if !ok {
		return Charge{}, false, ErrInFlight
	}
	if rec.declined {
		return rec.charge, true, fmt.Errorf("%w: %s", ErrDeclined, rec.charge.Reason)
	}
	return rec.charge, true, nil
}

func (g *Gateway) settle(req Request, rec record) {
	g.mu.Lock()
	g.settled[req.Key] = rec
	g.mu.Unlock()
}

func (g *Gateway) balance(currency string) int64 {
	g.mu.Lock()
	defer g.mu.Unlock()
	return g.balances[currency]
}

func (g *Gateway) debit(amount Money) {
	g.mu.Lock()
	g.balances[amount.Currency] -= amount.MinorUnits
	g.mu.Unlock()
}

// sweepLocked drops records past their TTL. Called under the lock, on every claim,
// which is enough at this size and keeps the gateway free of a background loop.
func (g *Gateway) sweepLocked() {
	cutoff := g.now().Add(-RecordTTL)
	for key, rec := range g.settled {
		if rec.storedAt.Before(cutoff) {
			delete(g.settled, key)
		}
	}
}

func newID() string {
	var b [6]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "ch_" + time.Now().Format("150405.000000")
	}
	return "ch_" + hex.EncodeToString(b[:])
}
