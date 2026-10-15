// Package api is the HTTP half: one endpoint that charges a card, one that reads
// a charge back, and a health check.
//
// The idempotency key travels in a header rather than the body, the way Stripe
// and Airwallex both take it — it belongs to the request, not to the payment.
package api

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"sync/atomic"
	"time"

	"metalcard/server/internal/gateway"
)

type API struct {
	gw  *gateway.Gateway
	log *slog.Logger

	// responsesToDrop swallows that many answers after the charge has been applied.
	// It is how the demo shows the case the whole design exists for.
	responsesToDrop atomic.Int64
	boot            time.Time
}

func New(gw *gateway.Gateway, log *slog.Logger, drop int64) *API {
	a := &API{gw: gw, log: log, boot: time.Now()}
	a.responsesToDrop.Store(drop)
	return a
}

func (a *API) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /v1/charges", a.createCharge)
	mux.HandleFunc("GET /v1/charges/{id}", a.getCharge)
	mux.HandleFunc("GET /healthz", a.health)
	return a.logging(mux)
}

type chargeRequest struct {
	Amount   gateway.Money `json:"amount"`
	Merchant string        `json:"merchant"`
	Last4    string        `json:"last4"`
}

type errorBody struct {
	Error     string `json:"error"`
	Message   string `json:"message"`
	Retriable bool   `json:"retriable"`
}

func (a *API) createCharge(w http.ResponseWriter, r *http.Request) {
	key := r.Header.Get("Idempotency-Key")
	if key == "" {
		writeError(w, http.StatusBadRequest, errorBody{"missing_idempotency_key",
			"send an Idempotency-Key header", false})
		return
	}

	var body chargeRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4<<10)).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, errorBody{"malformed_request", err.Error(), false})
		return
	}
	if body.Amount.MinorUnits <= 0 || body.Amount.Currency == "" {
		writeError(w, http.StatusBadRequest, errorBody{"invalid_amount",
			"amount.minor_units must be positive and amount.currency must be set", false})
		return
	}

	charge, replayed, err := a.gw.Authorize(gateway.Request{
		Key: key, Amount: body.Amount, Merchant: body.Merchant, Last4: body.Last4,
	})

	switch {
	case errors.Is(err, gateway.ErrKeyReused):
		writeError(w, http.StatusUnprocessableEntity, errorBody{"key_reused",
			"this Idempotency-Key was used with a different request", false})
		return
	case errors.Is(err, gateway.ErrInFlight):
		writeError(w, http.StatusConflict, errorBody{"request_in_flight",
			"the same key is already being charged", true})
		return
	case errors.Is(err, gateway.ErrDeclined):
		w.Header().Set("Idempotent-Replayed", boolHeader(replayed))
		writeJSON(w, http.StatusPaymentRequired, charge)
		return
	case err != nil:
		writeError(w, http.StatusInternalServerError, errorBody{"internal", err.Error(), true})
		return
	}

	// The money has moved. Dropping the answer here is exactly the case the
	// idempotency record exists for, so the client sees it in the demo.
	if a.responsesToDrop.Add(-1) >= 0 {
		a.log.Warn("dropping the response after the charge", "charge", charge.ID)
		hj, ok := w.(http.Hijacker)
		if ok {
			if conn, _, err := hj.Hijack(); err == nil {
				conn.Close()
				return
			}
		}
		writeError(w, http.StatusBadGateway, errorBody{"upstream_timeout",
			"no answer from the card network", true})
		return
	}

	w.Header().Set("Idempotent-Replayed", boolHeader(replayed))
	writeJSON(w, http.StatusOK, charge)
}

func (a *API) getCharge(w http.ResponseWriter, r *http.Request) {
	charge, ok := a.gw.Lookup(r.PathValue("id"))
	if !ok {
		writeError(w, http.StatusNotFound, errorBody{"not_found", "no such charge", false})
		return
	}
	writeJSON(w, http.StatusOK, charge)
}

func (a *API) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"status":  "ok",
		"uptime":  time.Since(a.boot).Round(time.Second).String(),
		"charges": a.gw.Charges(),
	})
}

func (a *API) logging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		a.log.Info("request",
			"method", r.Method, "path", r.URL.Path,
			"key", r.Header.Get("Idempotency-Key"),
			"took", time.Since(start).Round(time.Microsecond))
	})
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

func writeError(w http.ResponseWriter, status int, body errorBody) {
	writeJSON(w, status, body)
}

func boolHeader(b bool) string {
	if b {
		return "true"
	}
	return "false"
}
