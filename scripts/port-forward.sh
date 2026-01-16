#!/usr/bin/env bash
set -euo pipefail

# Port-forwards required services for the demo (excludes kube-state-metrics).
# - Prometheus (monitoring): 9090 -> 9090
# - Grafana (monitoring):    3000 -> 3000
# - Demo Go app (demo):      8080 -> 8080

declare -a PF_PIDS=()

cleanup() {
	if [[ ${#PF_PIDS[@]} -gt 0 ]]; then
		printf "\nStopping port-forwards...\n"
		for pid in "${PF_PIDS[@]}"; do
			if kill -0 "$pid" >/dev/null 2>&1; then
				kill "$pid" >/dev/null 2>&1 || true
			fi
		done
	fi
}
trap cleanup INT TERM EXIT

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found in PATH" >&2; exit 1; }
}

port_forward() {
	local ns="$1"; local kind="$2"; local name="$3"; local mapping="$4"
	# Verify resource exists
	if ! kubectl -n "$ns" get "$kind" "$name" >/dev/null 2>&1; then
		echo "Skip: $kind/$name not found in namespace '$ns'"
		return 0
	fi
	# Start port-forward in background
	echo "Port-forwarding $kind/$name in ns '$ns' on $mapping ..."
	kubectl -n "$ns" port-forward "$kind/$name" "$mapping" >/dev/null 2>&1 &
	PF_PIDS+=("$!")
}

main() {
	require_cmd kubectl

	# Prometheus
	port_forward monitoring svc prometheus 9090:9090

	# Grafana
	port_forward monitoring svc grafana 3000:3000

	# Demo Go app
	port_forward demo svc demo-go 8080:8080

	echo ""
	echo "Port-forwards running (Ctrl-C to stop):"
	echo "- Prometheus: http://localhost:9090"
	echo "- Grafana:    http://localhost:3000"
	echo "- Demo app:   http://localhost:8080"

	# Keep script alive while background port-forwards run
	wait
}

main "$@"


