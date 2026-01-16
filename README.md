## Local Observability Stack on kind — Design and Dev Notes

### Design Goals
- Capture design options, then choose the simplest, most transparent path for a local demo
- Keep manifests as plain YAML for clarity and reviewer transparency

### Decisions
- **Manifests format**: Pure YAML (no Helm)
- **Prometheus flavor**: Vanilla Prometheus (clearer to explain and inspect)
- **Storage**: Ephemeral (local demo; simpler; reset on pod restart/cluster delete)
- **Cluster metrics**: Use `kube-state-metrics` (KSM)

### Implementation Plan
1. Create kind cluster
2. Deploy `kube-state-metrics`
3. Deploy Prometheus
4. Deploy Grafana with Prometheus datasource and provisioned dashboards
5. Add a demo Go service exposing `/metrics`

### Prerequisites

| Tool | Purpose | Install |
|------|---------|---------|
| kubectl | Kubernetes CLI to interact with the cluster | [Install kubectl](https://kubernetes.io/docs/tasks/tools/) |
| kind | Run a local Kubernetes cluster in Docker | [Install kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) |
| Docker | Build demo image and provide Docker runtime for kind | [Install Docker](https://docs.docker.com/get-started/get-docker/) |
| Go 1.22+ | Build/run the demo Go app locally (optional) | [Install Go](https://go.dev/doc/install) |

### Quick start: one‑click setup
Use the provided scripts for a turnkey setup and access.

```bash
# One‑time: grant execute permission
chmod +x scripts/setup.sh scripts/port-forward.sh

# One‑click setup (creates cluster, deploys stack, builds & deploys demo app)
./scripts/setup.sh --port-forward
# Without automatic port‑forward: 
./luna/scripts/setup.sh

# You can re-run the port‑forward later on its own:
./scripts/port-forward.sh
```

### Timeline

| Task                                   | Time           |
|----------------------------------------|----------------|
| Design and plan (with AI help)         | 45 minutes     |
| Setup kind cluster, namespace          | 45 minutes     |
| Kube-state-metrics                     | 30 minutes     |
| Prometheus                             | 45 minutes     |
| Grafana                                | 30 minutes     |
| Go app                                 | 30 minutes     |
| Default built-in dashboard             | 1 hour         |
| README and scripts (AI)                | 30 minutes     |
| Testing and Monitoring                 | 45 minutes     |
| **Total**                              | **~6 hours**   |

### Repository Layout
- `infra/kind/kind-cluster.yaml`
- `k8s/namespaces/monitoring.yaml`
- `k8s/kube-state-metrics/`
- `k8s/prometheus/`
- `k8s/grafana/`
- `k8s/demo-go/`
- `apps/demo-go/`

---

## kind Cluster

References:
- kind install: `https://kind.sigs.k8s.io/docs/user/quick-start/#installation`
- kubectl install: `https://kubernetes.io/docs/tasks/tools/`
- Docker Desktop/Engine: `https://docs.docker.com/get-started/get-docker/`

Create the cluster:
```bash
kind create cluster --config infra/kind/kind-cluster.yaml
kubectl cluster-info --context kind-observability-cluster
```

Create the `monitoring` namespace:
```bash
kubectl apply -f k8s/namespaces/monitoring.yaml
kubectl get namespaces

# Optional: set default namespace for current context
kubectl config set-context --current --namespace=monitoring
```

---

## kube-state-metrics

Reference:
- KSM example manifests: `https://github.com/kubernetes/kube-state-metrics/tree/main/examples/standard`

Apply manifests (namespace set to `monitoring` in these files):
```bash
kubectl apply -k k8s/kube-state-metrics
kubectl -n monitoring rollout status deploy/kube-state-metrics
kubectl get deploy,po,svc -n monitoring
```

Validate metrics locally:
```bash
kubectl -n monitoring port-forward svc/kube-state-metrics 8080:8080
# in another shell
curl -s http://127.0.0.1:8080/metrics | head
```

---

## Prometheus (vanilla)

Reference:
- Example article: `https://devalpharm.medium.com/deploying-prometheus-and-grafana-on-kubernetes-using-manifest-files-3761792d12a4`

Deploy and validate:
```bash
kubectl apply -k k8s/prometheus
kubectl -n monitoring rollout status deploy/prometheus
kubectl get deploy,po,svc -n monitoring
```

Access UI:
```bash
kubectl -n monitoring port-forward svc/prometheus 9090:9090
# open http://localhost:9090
```

---

## Grafana

References:
- Same article as Prometheus above
- Design note: dashboards are auto-provisioned via files and picked up every ~30s

Apply manifests. Use server-side apply to avoid the client-side last-applied annotation size limit on large dashboard JSONs:
```bash
kubectl apply --server-side -k k8s/grafana
kubectl -n monitoring rollout status deploy/grafana
kubectl get deploy,po,svc -n monitoring
```

Access UI:
```bash
kubectl -n monitoring port-forward svc/grafana 3000:3000
# open http://localhost:3000
```

Notes:
- Both Prometheus and Grafana are also exposed via NodePort (Prometheus 30090, Grafana 30000) on the node IPs in kind.
- If you must use client-side apply, you can split dashboards across multiple ConfigMaps to avoid storing large last-applied annotations.

---

## Dashboards

Templates used:
- `https://grafana.com/grafana/dashboards/3662-prometheus-2-0-overview/`
- `https://grafana.com/grafana/dashboards/21742-object-s-health-kube-state-metrics-v2/`
- `https://grafana.com/grafana/dashboards/6671-go-processes/`

Notes:
- Some panels require kubelet cAdvisor metrics that are not included in this minimal setup.
- Datasource is set to the provisioned Prometheus UID.

---

## Demo Go App

Reference:
- Example guide: `https://crypto-gopher.medium.com/the-complete-guide-to-deploying-a-golang-application-to-kubernetes-ecd85a46c565`

Build and load image:
```bash
docker build -t demo-go:latest -f apps/demo-go/Dockerfile apps/demo-go
kind load docker-image --name observability-cluster demo-go:latest
```

Deploy and validate:
```bash
kubectl apply -k k8s/demo-go
kubectl -n demo rollout status deploy/demo-go
kubectl -n demo get pods
```

Access locally:
```bash
kubectl -n demo port-forward svc/demo-go 8080:8080
# http://localhost:8080/, /healthz, /readyz, /metrics
```

---

## Notes on AI Assistance
- Used AI to add a Grafana provider to auto-provision dashboards via ConfigMaps (instead of manual UI import)
- Adjusted dashboard JSON to reference the hardcoded Prometheus datasource UID
- Asked for CLI steps to validate components and for clarity on Prometheus pod-discovery configuration
- Helped set up the `demo-go` Dockerfile and Kubernetes Deployment/Service manifests, plus image build/load and rollout commands
- Broke down the design and tasks into smaller, timeboxed steps to limit scope and keep momentum
- Authored the app README and provided project-wide sanity-check guidance
