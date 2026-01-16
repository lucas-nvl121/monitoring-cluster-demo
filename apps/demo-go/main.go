package main

import (
	"context"
	"log/slog"
	"net"
	"net/http"
	"sync/atomic"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.uber.org/fx"
)

type Config struct {
	Addr string
}

type Readiness struct {
	ready atomic.Bool
}

func NewConfig() *Config {
	return &Config{
		Addr: ":8080",
	}
}

func NewReadiness() *Readiness { return &Readiness{} }

func NewRouter(r *Readiness) *gin.Engine {
	gin.SetMode(gin.ReleaseMode)

	router := gin.New()
	router.Use(gin.Recovery()) // Recover from panics
	router.Use(gin.Logger())   // Log requests
	router.GET("/", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"message": "Hello World!"})
	})
	router.GET("/metrics", gin.WrapH(promhttp.Handler()))
	router.GET("/healthz", func(c *gin.Context) { c.Status(http.StatusOK) })
	router.GET("/readyz", func(c *gin.Context) {
		if r.ready.Load() {
			c.Status(http.StatusOK)
		} else {
			c.Status(http.StatusServiceUnavailable)
		}
	})
	return router
}

func NewHTTPServer(cfg *Config, router *gin.Engine) *http.Server {
	return &http.Server{
		Addr:              cfg.Addr,
		Handler:           router,
		ReadHeaderTimeout: 5 * time.Second,
	}
}

func Run(lc fx.Lifecycle, server *http.Server, r *Readiness, cfg *Config) {
	lc.Append(fx.Hook{
		OnStart: func(ctx context.Context) error {
			slog.InfoContext(ctx, "Starting HTTP server", "addr", server.Addr)

			ln, err := net.Listen("tcp", server.Addr)
			if err != nil {
				return err
			}
			// Set readiness to true
			r.ready.Store(true)

			go func() {
				err := server.Serve(ln)
				if err != nil {
					panic(err)
				}
			}()

			return nil
		},
		OnStop: func(ctx context.Context) error {
			slog.InfoContext(ctx, "Stopping HTTP server.")

			ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
			defer cancel()

			r.ready.Store(false)
			return server.Shutdown(ctx)
		},
	})
}

func main() {
	fx.New(
		fx.Provide(
			NewConfig,
			NewReadiness,
			NewRouter,
			NewHTTPServer,
		),
		fx.Invoke(Run),
	).Run()
}
