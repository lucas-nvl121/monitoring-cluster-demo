## Demo Go App

A HTTP service exposing Prometheus metrics, built with Gin and Uber Fx. Includes health and readiness endpoints for Kubernetes.

### Features
- **HTTP framework**: Gin (`/` returns JSON)
- **Dependency injection & lifecycle**: Uber Fx (graceful shutdown)
- **Observability**: Prometheus metrics at `/metrics` (Go client default collectors)
- **Probes**: `/healthz` (liveness), `/readyz` (readiness)

### Requirements
- Go 1.22+

### Run locally
```bash
cd luna/apps/demo-go
go run .
# in another shell
curl -s http://localhost:8080/            # {"message":"Hello World!"}
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/healthz
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/readyz
curl -s http://localhost:8080/metrics | head
```

Build a local binary:
```bash
go build -o bin/demo-go ./...
./bin/demo-go
```

### Endpoints
- `GET /` → `{ "message": "Hello World!" }`
- `GET /healthz` → 200 when alive
- `GET /readyz` → 200 when ready (503 otherwise)
- `GET /metrics` → Prometheus metrics

### Notes
- The server listens on `:8080` by default.
- Readiness is toggled by the app at startup/shutdown via Fx lifecycle hooks.


