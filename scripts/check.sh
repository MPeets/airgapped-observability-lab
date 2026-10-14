#!/usr/bin/env bash
# Validates Prometheus and Alertmanager config, alert rules and routing,
# using the tools inside the pinned images. Nothing to install on the host.
set -euo pipefail
export MSYS_NO_PATHCONV=1  # stops Git Bash on Windows rewriting container paths

cd "$(dirname "$0")/.."

echo "== Prometheus =="
docker compose run --rm --no-deps -T --entrypoint sh prometheus -c '
  set -e
  promtool check config /etc/prometheus/prometheus.yml
  promtool test rules /etc/prometheus/tests/*.yml
'

echo "== Alertmanager =="
docker compose run --rm --no-deps -T --entrypoint sh alertmanager -c '
  set -e
  CFG=/etc/alertmanager/alertmanager.yml
  amtool check-config "$CFG"

  # route <expected receiver> <labels...>
  route() {
    expected="$1"; shift
    amtool config routes test --config.file="$CFG" --verify.receivers="$expected" "$@" >/dev/null \
      || { echo "FAIL: $* should route to $expected"; exit 1; }
    echo "ok: $* -> $expected"
  }

  route watchdog alertname=Watchdog severity=none
  route oncall   alertname=TargetDown severity=critical
  route oncall   alertname=HostDiskAlmostFull severity=critical
  route team     alertname=HostHighCpu severity=warning
  route oncall   alertname=ProbeFailed severity=critical
  route team     alertname=ProbeSlow severity=warning
  route team     alertname=TLSCertExpiringSoon severity=warning
  route oncall   alertname=TLSCertExpiryCritical severity=critical
  route default  alertname=SomethingUnlabelled
'

echo "== Blackbox exporter =="
docker compose run --rm --no-deps -T blackbox-exporter \
  --config.file=/etc/blackbox_exporter/blackbox.yml --config.check
  
echo "== Runbook links =="
# Every runbook link in an alert must point to a heading that exists in docs/runbook.md.
headings="$(grep -E '^## ' docs/runbook.md | sed 's/^## //' | tr -d '\r ' | tr '[:upper:]' '[:lower:]')"
missing=0
while read -r anchor; do
  if grep -qx "$anchor" <<< "$headings"; then
    echo "ok: #$anchor"
  else
    echo "FAIL: docs/runbook.md has no section for #$anchor"
    missing=1
  fi
done < <(grep -oE 'docs/runbook\.md#[a-z0-9-]+' prometheus/rules/*.yml | cut -d'#' -f2 | sort -u)
(( missing == 0 ))

echo "All checks passed."