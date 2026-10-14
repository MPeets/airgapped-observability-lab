#!/usr/bin/env bash
# End-to-end check of a running stack. Used by CI and handy after any change:
#
#   docker compose up -d && ./scripts/smoke-test.sh
#
# Waits up to TIMEOUT seconds (default 180) for each check, since targets,
# rules and notifications take a few scrape/evaluation cycles to settle.
# Needs only bash and curl, so it also works in Git Bash and on offline hosts.
set -euo pipefail
cd "$(dirname "$0")/.."

PROM=http://localhost:9090
AM=http://localhost:9093
GRAFANA=http://localhost:3000
TIMEOUT="${TIMEOUT:-180}"

GRAFANA_USER="$(grep -E '^GRAFANA_ADMIN_USER=' .env 2>/dev/null | cut -d= -f2- | tr -d '\r')"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PW="${GRAFANA_ADMIN_PASSWORD:-$(grep -E '^GRAFANA_ADMIN_PASSWORD=' .env | cut -d= -f2- | tr -d '\r')}"

# Single number from an instant PromQL query, without needing jq.
prom_value() {
  curl -sfG "$PROM/api/v1/query" --data-urlencode "query=$1" \
    | grep -o '"value":\[[^]]*\]' | head -1 | sed -E 's/.*,"([^"]*)"\]/\1/'
}

# wait_for <description> <command...>: retries until the command succeeds.
wait_for() {
  local what="$1"; shift
  local start=$SECONDS
  until "$@" >/dev/null 2>&1; do
    if (( SECONDS - start >= TIMEOUT )); then
      echo "FAIL  $what (gave up after ${TIMEOUT}s)"
      return 1
    fi
    sleep 5
  done
  echo "ok    $what ($(( SECONDS - start ))s)"
}

prom_equals() { [[ "$(prom_value "$1")" == "$2" ]]; }
prom_at_least() { local v; v="$(prom_value "$1")"; [[ -n "$v" ]] && (( ${v%.*} >= $2 )); }

failed=0
check() { wait_for "$@" || failed=1; }

check "Prometheus is ready"            curl -sf "$PROM/-/ready"
check "Alertmanager is ready"          curl -sf "$AM/-/ready"
check "Grafana is healthy"             curl -sf "$GRAFANA/api/health"

# The windows job is excluded: it depends on an exporter outside this stack.
check "all scrape targets are up"      prom_equals 'count(up{job!="windows"} == 0) or vector(0)' 0
check "at least 10 targets scraped"    prom_at_least 'count(up{job!="windows"})' 10
check "all blackbox probes succeed"    prom_equals 'count(probe_success == 0) or vector(0)' 0
check "recording rules produce data"   prom_at_least 'count(instance:cpu_utilisation:ratio)' 1
check "TLS certificate is valid"       prom_at_least 'min(probe_ssl_earliest_cert_expiry - time()) > 0 or vector(-1)' 1

check "Watchdog reached Alertmanager" \
  bash -c "curl -sfG '$AM/api/v2/alerts' --data-urlencode 'filter=alertname=\"Watchdog\"' | grep -q Watchdog"
check "Watchdog delivered to receiver" \
  bash -c "docker compose logs webhook-logger 2>/dev/null | grep -q '\[watchdog\] FIRING'"

check "dashboards are provisioned" \
  bash -c "curl -sf -u '$GRAFANA_USER:$GRAFANA_PW' '$GRAFANA/api/search?type=dash-db' \
    | grep -q host-overview && curl -sf -u '$GRAFANA_USER:$GRAFANA_PW' '$GRAFANA/api/search?type=dash-db' \
    | grep -q probes-certs"

echo
if (( failed )); then
  echo "Smoke test FAILED"
  exit 1
fi
echo "Smoke test passed"