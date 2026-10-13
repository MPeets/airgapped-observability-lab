#!/usr/bin/env bash
# Validates Prometheus config, rules and rule unit tests with the pinned promtool.
# Runs inside the Prometheus image, so nothing needs to be installed on the host.
set -euo pipefail
export MSYS_NO_PATHCONV=1  # stops Git Bash on Windows rewriting container paths

cd "$(dirname "$0")/.."

docker compose run --rm --no-deps -T --entrypoint sh prometheus -c '
  set -e
  echo "== config =="
  promtool check config /etc/prometheus/prometheus.yml
  echo "== rule unit tests =="
  promtool test rules /etc/prometheus/tests/*.yml
'