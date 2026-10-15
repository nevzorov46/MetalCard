// Command gatewayd serves the payment gateway MetalCard pays against.
//
//	go run ./cmd/gatewayd -addr :8080 -drop 1
//
// -drop swallows that many answers after the charge has gone through, which is
// the case the client's retry and the gateway's idempotency record exist for.
package main

import (
	"context"
	"errors"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"metalcard/server/internal/api"
	"metalcard/server/internal/gateway"
)

func main() {
	addr := flag.String("addr", ":8080", "address to listen on")
	drop := flag.Int64("drop", 0, "swallow this many responses after the charge has been applied")
	flag.Parse()

	log := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))

	srv := &http.Server{
		Addr:              *addr,
		Handler:           api.New(gateway.New(), log, *drop).Handler(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	go func() {
		log.Info("listening", "addr", *addr, "drop", *drop)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("serve", "err", err)
			os.Exit(1)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Error("shutdown", "err", err)
	}
	log.Info("stopped")
}
