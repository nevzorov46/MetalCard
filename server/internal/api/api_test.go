package api

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"metalcard/server/internal/gateway"
)

func newServer(t *testing.T, drop int64) (*httptest.Server, *gateway.Gateway) {
	t.Helper()
	gw := gateway.New()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	srv := httptest.NewServer(New(gw, log, drop).Handler())
	t.Cleanup(srv.Close)
	return srv, gw
}

func charge(t *testing.T, srv *httptest.Server, key string, minor int64) *http.Response {
	t.Helper()
	body, _ := json.Marshal(chargeRequest{
		Amount:   gateway.Money{MinorUnits: minor, Currency: "SGD"},
		Merchant: "Tamp & Grind", Last4: "4821",
	})
	req, err := http.NewRequest(http.MethodPost, srv.URL+"/v1/charges", bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Idempotency-Key", key)
	req.Header.Set("Content-Type", "application/json")
	res, err := srv.Client().Do(req)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { res.Body.Close() })
	return res
}

func TestChargeNeedsAKey(t *testing.T) {
	srv, _ := newServer(t, 0)
	res, err := srv.Client().Post(srv.URL+"/v1/charges", "application/json",
		bytes.NewReader([]byte(`{"amount":{"minor_units":480,"currency":"SGD"}}`)))
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusBadRequest {
		t.Errorf("status %d, want 400", res.StatusCode)
	}
}

func TestRetryAfterALostResponseChargesOnce(t *testing.T) {
	// The first answer never comes back, which is the whole case.
	srv, gw := newServer(t, 1)

	if _, err := srv.Client().Do(mustRequest(t, srv, "k1", 480)); err == nil {
		t.Log("the dropped response surfaced as a response rather than a broken pipe")
	}

	res := charge(t, srv, "k1", 480)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("status %d, want 200", res.StatusCode)
	}
	if got := res.Header.Get("Idempotent-Replayed"); got != "true" {
		t.Errorf("Idempotent-Replayed = %q, want true", got)
	}
	if n := gw.Charges(); n != 1 {
		t.Errorf("charged %d times, want 1", n)
	}
}

func TestReusingAKeyWithADifferentAmount(t *testing.T) {
	srv, _ := newServer(t, 0)
	charge(t, srv, "k1", 480)

	res := charge(t, srv, "k1", 48_000)
	if res.StatusCode != http.StatusUnprocessableEntity {
		t.Errorf("status %d, want 422", res.StatusCode)
	}
}

func TestDeclineComesBackAs402(t *testing.T) {
	srv, gw := newServer(t, 0)
	res := charge(t, srv, "k1", 999_999_99)
	if res.StatusCode != http.StatusPaymentRequired {
		t.Errorf("status %d, want 402", res.StatusCode)
	}
	var body gateway.Charge
	if err := json.NewDecoder(res.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}
	if body.Status != "declined" || body.Reason != "insufficient funds" {
		t.Errorf("body = %+v", body)
	}
	if n := gw.Charges(); n != 0 {
		t.Errorf("charged %d times, want 0", n)
	}
}

func TestReadAChargeBack(t *testing.T) {
	srv, _ := newServer(t, 0)
	res := charge(t, srv, "k1", 480)
	var made gateway.Charge
	if err := json.NewDecoder(res.Body).Decode(&made); err != nil {
		t.Fatal(err)
	}

	got, err := srv.Client().Get(srv.URL + "/v1/charges/" + made.ID)
	if err != nil {
		t.Fatal(err)
	}
	defer got.Body.Close()
	if got.StatusCode != http.StatusOK {
		t.Errorf("status %d, want 200", got.StatusCode)
	}
}

func TestHealth(t *testing.T) {
	srv, _ := newServer(t, 0)
	res, err := srv.Client().Get(srv.URL + "/healthz")
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Errorf("status %d, want 200", res.StatusCode)
	}
}

func mustRequest(t *testing.T, srv *httptest.Server, key string, minor int64) *http.Request {
	t.Helper()
	body, _ := json.Marshal(chargeRequest{
		Amount:   gateway.Money{MinorUnits: minor, Currency: "SGD"},
		Merchant: "Tamp & Grind", Last4: "4821",
	})
	req, err := http.NewRequest(http.MethodPost, srv.URL+"/v1/charges", bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Idempotency-Key", key)
	return req
}
