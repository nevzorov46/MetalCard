package gateway

import (
	"errors"
	"sync"
	"testing"
)

func req(key string, minor int64) Request {
	return Request{Key: key, Amount: Money{MinorUnits: minor, Currency: "SGD"},
		Merchant: "Tamp & Grind", Last4: "4821"}
}

func TestSameKeyTwiceIsOnePurchase(t *testing.T) {
	g := New()

	first, replayed, err := g.Authorize(req("k1", 480))
	if err != nil || replayed {
		t.Fatalf("first charge: err=%v replayed=%v", err, replayed)
	}
	second, replayed, err := g.Authorize(req("k1", 480))
	if err != nil {
		t.Fatalf("second charge: %v", err)
	}
	if !replayed {
		t.Error("the second call should have been a replay")
	}
	if first.ID != second.ID {
		t.Errorf("replay returned a different charge: %s vs %s", first.ID, second.ID)
	}
	if n := g.Charges(); n != 1 {
		t.Errorf("charged %d times, want 1", n)
	}
}

func TestNewKeyIsANewPurchase(t *testing.T) {
	g := New()
	if _, _, err := g.Authorize(req("k1", 480)); err != nil {
		t.Fatal(err)
	}
	if _, _, err := g.Authorize(req("k2", 480)); err != nil {
		t.Fatal(err)
	}
	if n := g.Charges(); n != 2 {
		t.Errorf("charged %d times, want 2", n)
	}
}

// The point of the fingerprint: a key stands for one request, not for whatever
// request happens to carry it. Replaying a €4.80 receipt for a €480 charge would
// be worse than charging twice.
func TestKeyReusedWithADifferentRequest(t *testing.T) {
	g := New()
	if _, _, err := g.Authorize(req("k1", 480)); err != nil {
		t.Fatal(err)
	}
	_, _, err := g.Authorize(req("k1", 48_000))
	if !errors.Is(err, ErrKeyReused) {
		t.Errorf("got %v, want ErrKeyReused", err)
	}
	if n := g.Charges(); n != 1 {
		t.Errorf("charged %d times, want 1", n)
	}
}

func TestDeclineIsRecordedAgainstTheKey(t *testing.T) {
	g := New()
	tooMuch := req("k1", 999_999_99)

	_, _, err := g.Authorize(tooMuch)
	if !errors.Is(err, ErrDeclined) {
		t.Fatalf("got %v, want ErrDeclined", err)
	}
	// The retry gets the same answer rather than a second look at the balance.
	_, replayed, err := g.Authorize(tooMuch)
	if !errors.Is(err, ErrDeclined) {
		t.Errorf("got %v, want ErrDeclined", err)
	}
	if !replayed {
		t.Error("the decline should have been replayed from the record")
	}
	if n := g.Charges(); n != 0 {
		t.Errorf("charged %d times, want 0", n)
	}
}

// Run with -race. Twenty goroutines, one key: exactly one of them may move money,
// and the rest must either replay it or be told the key is in flight.
func TestConcurrentDuplicatesChargeOnce(t *testing.T) {
	g := New()
	const callers = 20

	var wg sync.WaitGroup
	wg.Add(callers)
	for range callers {
		go func() {
			defer wg.Done()
			_, _, _ = g.Authorize(req("k1", 480))
		}()
	}
	wg.Wait()

	if n := g.Charges(); n != 1 {
		t.Errorf("charged %d times, want 1", n)
	}
}

func TestBalanceIsDebitedOnce(t *testing.T) {
	g := New()
	before := g.balance("SGD")

	for range 5 {
		_, _, _ = g.Authorize(req("k1", 480))
	}

	if after := g.balance("SGD"); after != before-480 {
		t.Errorf("balance went from %d to %d, want %d", before, after, before-480)
	}
}

func TestLookup(t *testing.T) {
	g := New()
	charge, _, err := g.Authorize(req("k1", 480))
	if err != nil {
		t.Fatal(err)
	}
	found, ok := g.Lookup(charge.ID)
	if !ok || found.ID != charge.ID {
		t.Errorf("lookup(%s) = %v, %v", charge.ID, found, ok)
	}
	if _, ok := g.Lookup("ch_nope"); ok {
		t.Error("found a charge that was never made")
	}
}
