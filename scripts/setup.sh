#!/usr/bin/env bash
set -euo pipefail

# One-shot setup of the local monitoring stack on kind
# - Creates kind cluster (if missing)
# - Applies monitoring namespace
# - Deploys kube-state-metrics, Prometheus, Grafana
# - Builds demo-go image, loads into kind, deploys demo-go

require() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found in PATH" >&2; exit 1; }; }
title() { printf "\n==> %s\n" "$1"; }
wait_rollout() { # ns kind name timeout
  kubectl -n "$1" rollout status "$2/$3" --timeout="${4:-180s}";
}

# Resolve repo root (script_dir/..)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

CLUSTER_NAME="observability-cluster"
ROLLOUT_TIMEOUT="180s"

# Args
START_PF=false
for arg in "$@"; do
  case "$arg" in
    --port-forward) START_PF=true ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

title "Checking prerequisites"
require kind
require kubectl
require docker

title "Ensuring kind cluster '$CLUSTER_NAME' exists"
if ! kind get clusters | grep -qx "$CLUSTER_NAME"; then
  kind create cluster --name "$CLUSTER_NAME" --config infra/kind/kind-cluster.yaml
else
  echo "kind cluster '$CLUSTER_NAME' already exists, skipping create."
fi
kubectl cluster-info --context "kind-$CLUSTER_NAME" >/dev/null

title "Applying monitoring namespace"
# Handle historical typo path gracefully
if [[ -f k8s/namespaces/monitoring.yaml ]]; then
  kubectl apply -f k8s/namespaces/monitoring.yaml
elif [[ -f k8s/namepsaces/monitoring.yaml ]]; then
  kubectl apply -f k8s/namepsaces/monitoring.yaml
else
  echo "WARNING: monitoring namespace manifest not found; proceeding (resources may create it themselves)."
fi

title "Deploying kube-state-metrics"
kubectl apply -k k8s/kube-state-metrics
wait_rollout monitoring deploy kube-state-metrics "$ROLLOUT_TIMEOUT"

title "Deploying Prometheus"
kubectl apply -k k8s/prometheus
wait_rollout monitoring deploy prometheus "$ROLLOUT_TIMEOUT" || wait_rollout monitoring deploy prometheus "$ROLLOUT_TIMEOUT"

title "Deploying Grafana (server-side apply to avoid large annotation issues)"
# Ensure generated ConfigMaps land in monitoring ns even if kustomization lacks namespace
kubectl apply --server-side -k k8s/grafana -n monitoring
wait_rollout monitoring deploy grafana "$ROLLOUT_TIMEOUT"

title "Building demo-go image"
docker build -t demo-go:latest -f apps/demo-go/Dockerfile apps/demo-go

title "Loading image into kind"
kind load docker-image --name "$CLUSTER_NAME" demo-go:latest

title "Deploying demo-go app"
kubectl apply -k k8s/demo-go
wait_rollout demo deploy demo-go "$ROLLOUT_TIMEOUT"

echo "==> Setup complete. Access services via port-forward or NodePort:"
echo "- Prometheus: kubectl -n monitoring port-forward svc/prometheus 9090:9090  # http://localhost:9090"
echo "- Grafana:    kubectl -n monitoring port-forward svc/grafana 3000:3000    # http://localhost:3000"
echo "- Demo app:   kubectl -n demo        port-forward svc/demo-go 8080:8080    # http://localhost:8080"


# Optionally start port-forward script
if [[ "$START_PF" == "true" ]]; then
  title "Starting port-forward (Ctrl-C to stop)"
  exec "$REPO_ROOT/scripts/port-forward.sh"
else
  if [[ -t 0 ]]; then
    read -r -p $'\nStart port-forward now? [y/N]: ' PF_ANSWER || true
    case "${PF_ANSWER:-}" in
      y|Y)
        title "Starting port-forward (Ctrl-C to stop)"
        exec "$REPO_ROOT/scripts/port-forward.sh"
        ;;
      *)
        echo "Skip port-forward. You can run: $REPO_ROOT/scripts/port-forward.sh"
        ;;
    esac
  fi
fi


